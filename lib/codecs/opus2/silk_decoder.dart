// SPDX-FileCopyrightText: 2023 The Pion community <https://pion.ly>
// SPDX-License-Identifier: MIT

// Package silk provides a Silk decoder.

import 'dart:math' as math;
import 'range_decoder.dart';
import 'silk_common.dart';
import 'icdf_data.dart';
import 'codebook_data.dart';

/// [SilkDecoder] maintains the state needed to decode a stream of Silk frames.
class SilkDecoder {
  final RangeDecoder _rangeDecoder = RangeDecoder();

  // Have we decoded a frame yet?
  bool haveDecoded = false;

  // Is the previous frame a voiced frame?
  bool isPreviousFrameVoiced = false;

  int previousLogGain = 0;

  // The decoder saves the final d_LPC values, i.e., lpc[i] such that
  // (j + n - d_LPC) <= i < (j + n), to feed into the LPC synthesis of the
  // next subframe. This requires storage for up to 16 values of lpc[i] (for WB frames).
  List<double> previousFrameLPCValues = [];

  // This requires storage to buffer up to 306 values of out[i] from previous subframes.
  // Ref: https://www.rfc-editor.org/rfc/rfc6716#section-4.2.7.9.1
  List<double> finalOutValues = List.filled(306, 0.0);

  // n0Q15 are the LSF coefficients decoded for the prior frame.
  // See normalizeLSFInterpolation.
  List<int> n0Q15 = [];

  /// Creates a new Silk Decoder.
  SilkDecoder();

  /// Decodes header bits.
  /// The LP layer begins with two to eight header bits These consist of one
  /// Voice Activity Detection (VAD) bit per frame (up to 3), followed by a
  /// single flag indicating the presence of LBRR frames.
  ///
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.3
  (bool voiceActivityDetected, bool lowBitRateRedundancy) decodeHeaderBits() {
    final voiceActivityDetected = _rangeDecoder.decodeSymbolLogP(1) == 1;
    final lowBitRateRedundancy = _rangeDecoder.decodeSymbolLogP(1) == 1;
    return (voiceActivityDetected, lowBitRateRedundancy);
  }

  /// Determines frame type.
  /// Each SILK frame contains a single "frame type" symbol that jointly
  /// codes the signal type and quantization offset type of the
  /// corresponding frame.
  ///
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.3
  (FrameSignalType signalType, FrameQuantizationOffsetType quantizationOffsetType)
      determineFrameType(bool voiceActivityDetected) {
    int frameTypeSymbol;
    if (voiceActivityDetected) {
      frameTypeSymbol = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfFrameTypeVADActive);
    } else {
      frameTypeSymbol = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfFrameTypeVADInactive);
    }

    // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.3
    switch (frameTypeSymbol) {
      case 0:
        if (!voiceActivityDetected) {
          return (FrameSignalType.inactive, FrameQuantizationOffsetType.low);
        } else {
          return (FrameSignalType.unvoiced, FrameQuantizationOffsetType.low);
        }
      case 1:
        if (!voiceActivityDetected) {
          return (FrameSignalType.inactive, FrameQuantizationOffsetType.high);
        } else {
          return (FrameSignalType.unvoiced, FrameQuantizationOffsetType.high);
        }
      case 2:
        // This case is only for voiced frames
        return (FrameSignalType.voiced, FrameQuantizationOffsetType.low);
      case 3:
        // This case is only for voiced frames
        return (FrameSignalType.voiced, FrameQuantizationOffsetType.high);
      default:
        // Should not happen with given ICDF tables
        throw Exception('Invalid frame type symbol: $frameTypeSymbol');
    }
  }

  /// Decodes subframe quantizations.
  /// A separate quantization gain is coded for each 5 ms subframe.
  ///
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.4
  List<double> decodeSubframeQuantizations(FrameSignalType signalType) {
    int logGain;
    int deltaGainIndex;
    List<double> gainQ16 = List.filled(SilkConstants.subframeCount, 0.0);

    for (int subframeIndex = 0; subframeIndex < SilkConstants.subframeCount; subframeIndex++) {
      if (subframeIndex == 0) {
        // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.4
        int gainIndex;
        switch (signalType) {
          case FrameSignalType.inactive:
            gainIndex = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfIndependentQuantizationGainMSBInactive);
            break;
          case FrameSignalType.voiced:
            gainIndex = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfIndependentQuantizationGainMSBVoiced);
            break;
          case FrameSignalType.unvoiced:
            gainIndex = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfIndependentQuantizationGainMSBUnvoiced);
            break;
        }

        gainIndex = (gainIndex << 3) | _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfIndependentQuantizationGainLSB);

        // When the gain for the previous subframe is available, then the
        // current gain is limited as follows:
        // log_gain = max(gain_index, previous_log_gain - 16)
        if (haveDecoded) {
          logGain = maxInt32(gainIndex, previousLogGain - 16);
        } else {
          logGain = gainIndex;
        }
      } else {
        // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.4
        deltaGainIndex = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfDeltaQuantizationGain);

        // log_gain = clamp(0, max(2*delta_gain_index - 16, previous_log_gain + delta_gain_index - 4), 63)
        logGain = clamp(0, maxInt32(2 * deltaGainIndex - 16, previousLogGain + deltaGainIndex - 4), 63);
      }

      previousLogGain = logGain;

      // silk_gains_dequant() (gain_quant.c) dequantizes log_gain for the k'th
      // subframe and converts it into a linear Q16 scale factor via
      // gain_Q16[k] = silk_log2lin((0x1D1C71*log_gain>>16) + 2090)
      final int inLogQ7 = ((0x1D1C71 * logGain) >> 16) + 2090;
      final int i = inLogQ7 >> 7; // integer exponent
      final int f = inLogQ7 & 127; // fractional exponent

      // The function silk_log2lin() (log2lin.c) computes an approximation of
      // 2**(inLog_Q7/128.0), where inLog_Q7 is its Q7 input.  Let i =
      // inLog_Q7>>7 be the integer part of inLogQ7 and f = inLog_Q7&127 be
      // the fractional part.  Then,
      // (1<<i) + ((-174*f*(128-f)>>16)+f)*((1<<i)>>7)
      // yields the approximate exponential.
      double val = (1 << i).toDouble();
      val += ((-174 * f * (128 - f)) >> 16).toDouble() + f.toDouble();
      val *= ((1 << i) >> 7).toDouble(); // Corrected order of operations
      val += (1 << i).toDouble(); // Add the original (1<<i) back

      gainQ16[subframeIndex] = val;
    }
    return gainQ16;
  }

  /// Decodes the first stage of normalized Line Spectral Frequency (LSF) coefficients.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.1
  int normalizeLineSpectralFrequencyStageOne(bool voiceActivityDetected, Bandwidth bandwidth) {
    int I1;
    if (!voiceActivityDetected && (bandwidth == Bandwidth.narrowband || bandwidth == Bandwidth.mediumband)) {
      I1 = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFStageOneIndexNarrowbandOrMediumbandUnvoiced);
    } else if (voiceActivityDetected && (bandwidth == Bandwidth.narrowband || bandwidth == Bandwidth.mediumband)) {
      I1 = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFStageOneIndexNarrowbandOrMediumbandVoiced);
    } else if (!voiceActivityDetected && (bandwidth == Bandwidth.wideband)) {
      I1 = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFStageOneIndexWidebandUnvoiced);
    } else {
      // voiceActivityDetected && (bandwidth == Bandwidth.wideband)
      I1 = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFStageOneIndexWidebandVoiced);
    }
    return I1;
  }

  /// Decodes the second stage of normalized Line Spectral Frequency (LSF) coefficients.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.2
  (int dLPC, List<int> resQ10) normalizeLineSpectralFrequencyStageTwo(Bandwidth bandwidth, int I1) {
    List<List<int>> codebook;
    if (bandwidth == Bandwidth.wideband) {
      codebook = CodebookData.codebookNormalizedLSFStageTwoIndexWideband;
    } else {
      codebook = CodebookData.codebookNormalizedLSFStageTwoIndexNarrowbandOrMediumband;
    }

    final I2 = List<int>.filled(codebook[0].length, 0);
    for (int i = 0; i < I2.length; i++) {
      // Subtracts 4 from the result to give an index in the range -4 to 4, inclusive.
      // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.2
      I2[i] = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFStageTwoIndex[codebook[I1][i]]) - 4;

      // If the index is either -4 or 4, it reads a second symbol using the PDF in
      // Table 19, and adds the value of this second symbol to the index,
      // using the same sign. This gives the index, I2[k], a total range of
      // -10 to 10, inclusive.
      // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.2
      if (I2[i] == -4) {
        I2[i] -= _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFStageTwoIndexExtension);
      } else if (I2[i] == 4) {
        I2[i] += _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFStageTwoIndexExtension);
      }
    }

    int qstep;
    if (bandwidth == Bandwidth.wideband) {
      qstep = 9830;
    } else {
      qstep = 11796;
    }

    final dLPC = I2.length;
    final resQ10 = List<int>.filled(dLPC, 0);

    // for 0 <= k < d_LPC-1
    for (int k = dLPC - 1; k >= 0; k--) {
      // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.2
      int firstOperand = 0;
      if (k + 1 < dLPC) {
        int predQ8;
        if (bandwidth == Bandwidth.wideband) {
          predQ8 = CodebookData.predictionWeightForWidebandNormalizedLSF[
              CodebookData.predictionWeightSelectionForWidebandNormalizedLSF[I1][k]][k];
        } else {
          predQ8 = CodebookData.predictionWeightForNarrowbandAndMediumbandNormalizedLSF[
              CodebookData.predictionWeightSelectionForNarrowbandAndMediumbandNormalizedLSF[I1][k]][k];
        }
        firstOperand = (resQ10[k + 1] * predQ8) >> 8;
      }

      final secondOperand = (((I2[k] << 10) - sign(I2[k]) * 102) * qstep) >> 16;
      resQ10[k] = firstOperand + secondOperand;
    }
    return (dLPC, resQ10);
  }

  /// Reconstructs the final normalized LSF coefficients.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.3
  List<int> normalizeLineSpectralFrequencyCoefficients(
      int dLPC, Bandwidth bandwidth, List<int> resQ10, int I1) {
    final nlsfQ15 = List<int>.filled(dLPC, 0);
    final w2Q18 = List<int>.filled(dLPC, 0);
    final wQ9 = List<int>.filled(dLPC, 0);

    List<List<int>> cb1Q8;
    if (bandwidth == Bandwidth.wideband) {
      cb1Q8 = CodebookData.codebookNormalizedLSFStageOneWideband;
    } else {
      cb1Q8 = CodebookData.codebookNormalizedLSFStageOneNarrowbandOrMediumband;
    }

    for (int k = 0; k < dLPC; k++) {
      int kMinusOne = 0;
      int kPlusOne = 256;
      if (k != 0) {
        kMinusOne = cb1Q8[I1][k - 1];
      }
      if (k + 1 != dLPC) {
        kPlusOne = cb1Q8[I1][k + 1];
      }

      // w2_Q18[k] = (1024/(cb1_Q8[k] - cb1_Q8[k-1]) + 1024/(cb1_Q8[k+1] - cb1_Q8[k])) << 16
      w2Q18[k] = ((1024 ~/ (cb1Q8[I1][k] - kMinusOne)) + (1024 ~/ (kPlusOne - cb1Q8[I1][k]))) << 16;

      // Square-root approximation for w_Q9[k]
      // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.3
      final i = ilog(w2Q18[k]);
      final f = (w2Q18[k] >> (i - 8)) & 127;

      int y = 46214;
      if ((i & 1) != 0) {
        y = 32768;
      }
      y >>= ((32 - i) >> 1);
      wQ9[k] = y + ((213 * f * y) >> 16);

      // NLSF_Q15[k] = clamp(0, (cb1_Q8[k]<<7) + (res_Q10[k]<<14)/w_Q9[k], 32767)
      nlsfQ15[k] = clamp(0, (cb1Q8[I1][k] << 7) + ((resQ10[k] << 14) ~/ wQ9[k]), 32767);
    }
    return nlsfQ15;
  }

  /// Normalizes LSF stabilization.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.4
  void normalizeLSFStabilization(List<int> nlsfQ15, int dLPC, Bandwidth bandwidth) {
    List<int> nDeltaMinQ15;
    if (bandwidth == Bandwidth.wideband) {
      nDeltaMinQ15 = CodebookData.codebookMinimumSpacingForNormalizedLSCoefficientsWideband;
    } else {
      nDeltaMinQ15 = CodebookData.codebookMinimumSpacingForNormalizedLSCoefficientsNarrowbandAndMediumband;
    }

    for (int adjustment = 0; adjustment <= 19; adjustment++) {
      int i = 0;
      int iValue = (1 << 31) - 1; // Represents math.MaxInt (for a 32-bit signed int)

      for (int nlsfIndex = 0; nlsfIndex <= nlsfQ15.length; nlsfIndex++) {
        int previousNLSF = 0;
        int currentNLSF = 32768;
        if (nlsfIndex != 0) {
          previousNLSF = nlsfQ15[nlsfIndex - 1];
        }
        if (nlsfIndex != nlsfQ15.length) {
          currentNLSF = nlsfQ15[nlsfIndex];
        }

        final spacingValue = currentNLSF - previousNLSF - nDeltaMinQ15[nlsfIndex];
        if (spacingValue < iValue) {
          i = nlsfIndex;
          iValue = spacingValue;
        }
      }

      if (iValue >= 0) {
        return; // Coefficients satisfy constraints
      } else if (i == 0) {
        nlsfQ15[0] = nDeltaMinQ15[0];
      } else if (i == dLPC) {
        nlsfQ15[dLPC - 1] = 32768 - nDeltaMinQ15[dLPC];
      } else {
        int minCenterQ15 = nDeltaMinQ15[i] >> 1;
        for (int k = 0; k <= i - 1; k++) {
          minCenterQ15 += nDeltaMinQ15[k];
        }

        int maxCenterQ15 = 32768 - (nDeltaMinQ15[i] >> 1);
        for (int k = i + 1; k <= dLPC; k++) {
          maxCenterQ15 -= nDeltaMinQ15[k];
        }

        final centerFreqQ15 = clamp(
          minCenterQ15,
          (nlsfQ15[i - 1] + nlsfQ15[i] + 1) >> 1,
          maxCenterQ15,
        );

        nlsfQ15[i - 1] = centerFreqQ15 - (nDeltaMinQ15[i] >> 1);
        nlsfQ15[i] = nlsfQ15[i - 1] + nDeltaMinQ15[i];
      }
    }

    // Fallback procedure after 20 adjustments
    nlsfQ15.sort((a, b) => a.compareTo(b));

    for (int k = 0; k <= dLPC - 1; k++) {
      int prevNLSF = 0;
      if (k != 0) {
        prevNLSF = nlsfQ15[k - 1];
      }
      nlsfQ15[k] = maxInt16(nlsfQ15[k], prevNLSF + nDeltaMinQ15[k]);
    }

    for (int k = dLPC - 1; k >= 0; k--) {
      int nextNLSF = 32768;
      if (k != dLPC - 1) {
        nextNLSF = nlsfQ15[k + 1];
      }
      nlsfQ15[k] = minInt16(nlsfQ15[k], nextNLSF - nDeltaMinQ15[k + 1]);
    }
  }

  /// Normalizes LSF interpolation.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.5
  (List<int>? n1Q15, int wQ2) normalizeLSFInterpolation(List<int> n2Q15) {
    final wQ2 = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfNormalizedLSFInterpolationIndex);
    if (wQ2 == 4 || !haveDecoded) {
      return (null, wQ2);
    }

    final n1Q15 = List<int>.filled(n2Q15.length, 0);
    for (int k = 0; k < n1Q15.length; k++) {
      n1Q15[k] = n0Q15[k] + (wQ2 * (n2Q15[k] - n0Q15[k]) >> 2);
    }
    return (n1Q15, wQ2);
  }

  /// Generates A_Q12 coefficients.
  List<List<double>> generateAQ12(List<int>? q15, Bandwidth bandwidth, List<List<double>> aQ12) {
    if (q15 == null) {
      return aQ12;
    }

    // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.6
    final a32Q17 = _convertNormalizedLSFsToLPCCoefficients(q15, bandwidth);

    // Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.5.7
    _limitLPCCoefficientsRange(a32Q17);

    // Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.5.8
    aQ12.add(_limitLPCFilterPredictionGain(a32Q17));

    return aQ12;
  }

  /// Converts normalized LSFs to LPC coefficients.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.6
  List<int> _convertNormalizedLSFsToLPCCoefficients(List<int> n1Q15, Bandwidth bandwidth) {
    final cQ17 = List<int>.filled(n1Q15.length, 0);
    final cosQ12 = CodebookData.q12CosineTableForLSFConversion;

    final ordering = bandwidth == Bandwidth.wideband
        ? CodebookData.lsfOrderingForPolynomialEvaluationWideband
        : CodebookData.lsfOrderingForPolynomialEvaluationNarrowbandAndMediumband;

    for (int k = 0; k < n1Q15.length; k++) {
      final int i = n1Q15[k] >> 8;
      final int f = n1Q15[k] & 255;

      cQ17[ordering[k]] = (cosQ12[i] * 256 + (cosQ12[i + 1] - cosQ12[i]) * f + 4) >> 3;
    }

    final int dLPC = n1Q15.length;
    final int d2 = dLPC ~/ 2;

    final pQ16 = List<int>.filled(d2 + 1, 0);
    final qQ16 = List<int>.filled(d2 + 1, 0);

    pQ16[0] = 1 << 16;
    qQ16[0] = 1 << 16;
    pQ16[1] = -cQ17[0];
    qQ16[1] = -cQ17[1];

    // Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.6
    for (int k = 1; k < d2; k++) {
      pQ16[k + 1] = pQ16[k - 1] * 2 - (((cQ17[2 * k] * pQ16[k]) + 32768) >> 16);
      qQ16[k + 1] = qQ16[k - 1] * 2 - (((cQ17[(2 * k) + 1] * qQ16[k]) + 32768) >> 16);

      for (int j = k; j > 1; j--) {
        pQ16[j] += pQ16[j - 2] - (((cQ17[2 * k] * pQ16[j - 1]) + 32768) >> 16);
        qQ16[j] += qQ16[j - 2] - (((cQ17[(2 * k) + 1] * qQ16[j - 1]) + 32768) >> 16);
      }

      pQ16[1] -= cQ17[2 * k];
      qQ16[1] -= cQ17[2 * k + 1];
    }

    final a32Q17 = List<int>.filled(dLPC, 0);
    for (int k = 0; k < d2; k++) {
      a32Q17[k] = -(qQ16[k + 1] - qQ16[k]) - (pQ16[k + 1] + pQ16[k]);
      a32Q17[dLPC - k - 1] = (qQ16[k + 1] - qQ16[k]) - (pQ16[k + 1] + pQ16[k]);
    }
    return a32Q17;
  }

  /// Decodes Linear Congruential Generator seed.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.7
  int decodeLinearCongruentialGeneratorSeed() {
    return _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfLinearCongruentialGeneratorSeed);
  }

  /// Decodes shell blocks.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8
  int decodeShellblocks(int nanoseconds, Bandwidth bandwidth) {
    if (nanoseconds == SilkConstants.nanoseconds10Ms) {
      if (bandwidth == Bandwidth.narrowband) {
        return 5;
      } else if (bandwidth == Bandwidth.mediumband) {
        return 8;
      } else {
        // Bandwidth.wideband
        return 10;
      }
    } else if (nanoseconds == SilkConstants.nanoseconds20Ms) {
      if (bandwidth == Bandwidth.narrowband) {
        return 10;
      } else if (bandwidth == Bandwidth.mediumband) {
        return 15;
      } else {
        // Bandwidth.wideband
        return 20;
      }
    }
    return 0; // Should not happen with valid inputs
  }

  /// Decodes rate level.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8.1
  int decodeRatelevel(bool voiceActivityDetected) {
    if (voiceActivityDetected) {
      return _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfRateLevelVoiced);
    }
    return _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfRateLevelUnvoiced);
  }

  /// Decodes pulse and LSB counts.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8.2
  (List<int> pulsecounts, List<int> lsbcounts) decodePulseAndLSBCounts(int shellblocks, int rateLevel) {
    final pulsecounts = List<int>.filled(shellblocks, 0);
    final lsbcounts = List<int>.filled(shellblocks, 0);
    for (int i = 0; i < shellblocks; i++) {
      pulsecounts[i] = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfPulseCount[rateLevel]);

      if (pulsecounts[i] == 17) {
        int lsbcount = 0;
        while (pulsecounts[i] == 17 && lsbcount < 10) {
          pulsecounts[i] = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfPulseCount[9]);
          lsbcount++;
        }
        lsbcounts[i] = lsbcount;

        if (lsbcount == 10) {
          pulsecounts[i] = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfPulseCount[10]);
        }
      }
    }
    return (pulsecounts, lsbcounts);
  }

  /// Decodes pulse locations.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8.3
  List<int> decodePulseLocation(List<int> pulsecounts) {
    final eRaw = List<int>.filled(pulsecounts.length * SilkConstants.pulsecountLargestPartitionSize, 0);
    for (int i = 0; i < pulsecounts.length; i++) {
      if (pulsecounts[i] == 0) {
        continue;
      }

      int eRawIndex = SilkConstants.pulsecountLargestPartitionSize * i;
      final samplePartition16 = List<int>.filled(2, 0);
      final samplePartition8 = List<int>.filled(2, 0);
      final samplePartition4 = List<int>.filled(2, 0);
      final samplePartition2 = List<int>.filled(2, 0);

      _partitionPulseCount(IcdfData.icdfPulseCountSplit16SamplePartitions, pulsecounts[i], samplePartition16);
      for (int j = 0; j < 2; j++) {
        _partitionPulseCount(IcdfData.icdfPulseCountSplit8SamplePartitions, samplePartition16[j], samplePartition8);
        for (int k = 0; k < 2; k++) {
          _partitionPulseCount(IcdfData.icdfPulseCountSplit4SamplePartitions, samplePartition8[k], samplePartition4);
          for (int l = 0; l < 2; l++) {
            _partitionPulseCount(IcdfData.icdfPulseCountSplit2SamplePartitions, samplePartition4[l], samplePartition2);
            eRaw[eRawIndex] = samplePartition2[0];
            eRawIndex++;

            eRaw[eRawIndex] = samplePartition2[1];
            eRawIndex++;
          }
        }
      }
    }
    return eRaw;
  }

  /// Decodes excitation LSBs.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8.4
  void decodeExcitationLSB(List<int> eRaw, List<int> lsbcounts) {
    for (int i = 0; i < eRaw.length; i++) {
      for (int bit = 0; bit < lsbcounts[i ~/ SilkConstants.pulsecountLargestPartitionSize]; bit++) {
        eRaw[i] = (eRaw[i] << 1) | _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfExcitationLSB);
      }
    }
  }

  /// Decodes excitation signs.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8.5
  void decodeExcitationSign(List<int> eRaw, FrameSignalType signalType,
      FrameQuantizationOffsetType quantizationOffsetType, List<int> pulsecounts) {
    for (int i = 0; i < eRaw.length; i++) {
      if (eRaw[i] == 0) {
        continue;
      }

      List<int> icdf;
      final int pulsecount = pulsecounts[i ~/ SilkConstants.pulsecountLargestPartitionSize];

      switch (signalType) {
        case FrameSignalType.inactive:
          switch (quantizationOffsetType) {
            case FrameQuantizationOffsetType.low:
              switch (pulsecount) {
                case 0:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalLowQuantization0Pulse;
                  break;
                case 1:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalLowQuantization1Pulse;
                  break;
                case 2:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalLowQuantization2Pulse;
                  break;
                case 3:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalLowQuantization3Pulse;
                  break;
                case 4:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalLowQuantization4Pulse;
                  break;
                case 5:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalLowQuantization5Pulse;
                  break;
                default:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalLowQuantization6PlusPulse;
                  break;
              }
              break;
            case FrameQuantizationOffsetType.high:
              switch (pulsecount) {
                case 0:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalHighQuantization0Pulse;
                  break;
                case 1:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalHighQuantization1Pulse;
                  break;
                case 2:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalHighQuantization2Pulse;
                  break;
                case 3:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalHighQuantization3Pulse;
                  break;
                case 4:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalHighQuantization4Pulse;
                  break;
                case 5:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalHighQuantization5Pulse;
                  break;
                default:
                  icdf = IcdfData.icdfExcitationSignInactiveSignalHighQuantization6PlusPulse;
                  break;
              }
              break;
          }
          break;
        case FrameSignalType.unvoiced:
          switch (quantizationOffsetType) {
            case FrameQuantizationOffsetType.low:
              switch (pulsecount) {
                case 0:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalLowQuantization0Pulse;
                  break;
                case 1:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalLowQuantization1Pulse;
                  break;
                case 2:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalLowQuantization2Pulse;
                  break;
                case 3:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalLowQuantization3Pulse;
                  break;
                case 4:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalLowQuantization4Pulse;
                  break;
                case 5:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalLowQuantization5Pulse;
                  break;
                default:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalLowQuantization6PlusPulse;
                  break;
              }
              break;
            case FrameQuantizationOffsetType.high:
              switch (pulsecount) {
                case 0:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalHighQuantization0Pulse;
                  break;
                case 1:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalHighQuantization1Pulse;
                  break;
                case 2:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalHighQuantization2Pulse;
                  break;
                case 3:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalHighQuantization3Pulse;
                  break;
                case 4:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalHighQuantization4Pulse;
                  break;
                case 5:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalHighQuantization5Pulse;
                  break;
                default:
                  icdf = IcdfData.icdfExcitationSignUnvoicedSignalHighQuantization6PlusPulse;
                  break;
              }
              break;
          }
          break;
        case FrameSignalType.voiced:
          switch (quantizationOffsetType) {
            case FrameQuantizationOffsetType.low:
              switch (pulsecount) {
                case 0:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalLowQuantization0Pulse;
                  break;
                case 1:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalLowQuantization1Pulse;
                  break;
                case 2:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalLowQuantization2Pulse;
                  break;
                case 3:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalLowQuantization3Pulse;
                  break;
                case 4:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalLowQuantization4Pulse;
                  break;
                case 5:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalLowQuantization5Pulse;
                  break;
                default:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalLowQuantization6PlusPulse;
                  break;
              }
              break;
            case FrameQuantizationOffsetType.high:
              switch (pulsecount) {
                case 0:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalHighQuantization0Pulse;
                  break;
                case 1:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalHighQuantization1Pulse;
                  break;
                case 2:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalHighQuantization2Pulse;
                  break;
                case 3:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalHighQuantization3Pulse;
                  break;
                case 4:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalHighQuantization4Pulse;
                  break;
                case 5:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalHighQuantization5Pulse;
                  break;
                default:
                  icdf = IcdfData.icdfExcitationSignVoicedSignalHighQuantization6PlusPulse;
                  break;
              }
              break;
          }
          break;
      }

      if (_rangeDecoder.decodeSymbolWithICDF(icdf) == 0) {
        eRaw[i] *= -1;
      }
    }
  }

  /// Decodes excitation.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8.6
  List<int> decodeExcitation(FrameSignalType signalType, FrameQuantizationOffsetType quantizationOffsetType,
      int seed, List<int> pulsecounts, List<int> lsbcounts) {
    int offsetQ23;
    switch (signalType) {
      case FrameSignalType.inactive:
        offsetQ23 = quantizationOffsetType == FrameQuantizationOffsetType.low ? 25 : 60;
        break;
      case FrameSignalType.unvoiced:
        offsetQ23 = quantizationOffsetType == FrameQuantizationOffsetType.low ? 25 : 60;
        break;
      case FrameSignalType.voiced:
        offsetQ23 = quantizationOffsetType == FrameQuantizationOffsetType.low ? 8 : 25;
        break;
    }

    final eRaw = decodePulseLocation(pulsecounts);
    decodeExcitationLSB(eRaw, lsbcounts);
    decodeExcitationSign(eRaw, signalType, quantizationOffsetType, pulsecounts);

    final eQ23 = List<int>.filled(eRaw.length, 0);
    for (int i = 0; i < eRaw.length; i++) {
      eQ23[i] = (eRaw[i] << 8) - (sign(eRaw[i]) * 20) + offsetQ23;
      seed = (196314165 * seed + 907633515) & 0xFFFFFFFF; // Mask to simulate uint32
      if ((seed & 0x80000000) != 0) {
        eQ23[i] *= -1;
      }
      seed = (seed + eRaw[i]) & 0xFFFFFFFF; // Mask to simulate uint32
    }
    return eQ23;
  }

  /// Partitions pulse count.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.8.3
  void _partitionPulseCount(List<List<int>> icdf, int block, List<int> halves) {
    if (block == 0) {
      halves[0] = 0;
      halves[1] = 0;
    } else {
      halves[0] = _rangeDecoder.decodeSymbolWithICDF(icdf[block - 1]);
      halves[1] = block - halves[0];
    }
  }

  /// Limits LPC coefficients range.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.7
  void _limitLPCCoefficientsRange(List<int> a32Q17) {
    int bandwidthExpansionRound = 0;
    for (; bandwidthExpansionRound < 10; bandwidthExpansionRound++) {
      int maxabsQ17K = 0;
      int maxabsQ17 = 0;

      for (int k = 0; k < a32Q17.length; k++) {
        final int val = a32Q17[k];
        final int absVal = (sign(val) * val).abs();
        if (maxabsQ17 < absVal) {
          maxabsQ17K = k;
          maxabsQ17 = absVal;
        }
      }

      int maxabsQ12 = minUint((maxabsQ17 + 16) >> 5, 163838);

      if (maxabsQ12 > 32767) {
        final scQ16 = List<int>.filled(a32Q17.length + 1, 0); // +1 for scQ16[k+1]
        scQ16[0] = 65470;
        scQ16[0] -= ((maxabsQ12 - 32767) << 14) ~/ ((maxabsQ12 * (maxabsQ17K + 1)) >> 2);

        for (int k = 0; k < a32Q17.length; k++) {
          a32Q17[k] = (a32Q17[k] * scQ16[k]) >> 16;
          if (k + 1 < scQ16.length) {
            scQ16[k + 1] = (scQ16[0] * scQ16[k] + 32768) >> 16;
          }
        }
      } else {
        break;
      }
    }

    if (bandwidthExpansionRound == 9) {
      for (int k = 0; k < a32Q17.length; k++) {
        a32Q17[k] = (clamp(-32768, (a32Q17[k] + 16) >> 5, 32767)) << 5;
      }
    }
  }

  /// Limits LPC filter prediction gain.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.7.5.8
  List<double> _limitLPCFilterPredictionGain(List<int> a32Q17) {
    final aQ12 = List<double>.filled(a32Q17.length, 0.0);
    for (int n = 0; n < a32Q17.length; n++) {
      aQ12[n] = ((a32Q17[n] + 16) >> 5).toDouble();
    }
    return aQ12;
  }

  /// Decodes pitch lags.
  /// Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.6.1
  (int lagMax, List<int>? pitchLags, SilkError? err) decodePitchLags(
      FrameSignalType signalType, Bandwidth bandwidth) {
    if (signalType != FrameSignalType.voiced) {
      return (0, null, null);
    }

    int lag;
    int lagMin = 0;
    int lagMax = 0;

    // Assuming absolute coding for simplicity as non-absolute is unsupported in Go code.
    // Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.6.1
    //
    // Table 30: PDF for Low Part of Primary Pitch Lag
    List<int> lowPartICDF;
    int lagScale;

    switch (bandwidth) {
      case Bandwidth.narrowband:
        lowPartICDF = IcdfData.icdfPrimaryPitchLagLowPartNarrowband;
        lagScale = 4;
        lagMin = 16;
        lagMax = 144;
        break;
      case Bandwidth.mediumband:
        lowPartICDF = IcdfData.icdfPrimaryPitchLagLowPartMediumband;
        lagScale = 6;
        lagMin = 24;
        lagMax = 216;
        break;
      case Bandwidth.wideband:
        lowPartICDF = IcdfData.icdfPrimaryPitchLagLowPartWideband;
        lagScale = 8;
        lagMin = 32;
        lagMax = 288;
        break;
    }

    final lagHigh = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfPrimaryPitchLagHighPart);
    final lagLow = _rangeDecoder.decodeSymbolWithICDF(lowPartICDF);

    lag = lagHigh * lagScale + lagLow + lagMin;

    List<List<int>> lagCb;
    List<int> lagIcdf;

    switch (bandwidth) {
      case Bandwidth.narrowband:
        lagCb = CodebookData.codebookSubframePitchCounterNarrowband20Ms;
        lagIcdf = IcdfData.icdfSubframePitchContourNarrowband20Ms;
        break;
      case Bandwidth.mediumband:
      case Bandwidth.wideband:
        lagCb = CodebookData.codebookSubframePitchCounterMediumbandOrWideband20Ms;
        lagIcdf = IcdfData.icdfSubframePitchContourMediumbandOrWideband20Ms;
        break;
    }

    final contourIndex = _rangeDecoder.decodeSymbolWithICDF(lagIcdf);

    final pitchLags = List<int>.filled(SilkConstants.subframeCount, 0);
    for (int i = 0; i < SilkConstants.subframeCount; i++) {
      pitchLags[i] = clamp(lagMin, lag + lagCb[contourIndex][i], lagMax);
    }

    return (lagMax, pitchLags, null);
  }

  /// Decodes LTP scaling parameter.
  /// Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.6.3
  double decodeLTPScalingParamater(FrameSignalType signalType) {
    if (signalType != FrameSignalType.voiced) {
      return 15565.0;
    }

    final scaleFactorIndex = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfLTPScalingParameter);
    switch (scaleFactorIndex) {
      case 0:
        return 15565.0;
      case 1:
        return 12288.0;
      case 2:
        return 8192.0;
    }
    return 0.0;
  }

  /// Decodes LTP filter coefficients.
  /// Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.6.2
  List<List<int>> decodeLTPFilterCoefficients(FrameSignalType signalType) {
    final bQ7 = List<List<int>>.generate(SilkConstants.subframeCount, (index) => List<int>.filled(5, 0));

    if (signalType != FrameSignalType.voiced) {
      return bQ7;
    }

    final periodicityIndex = _rangeDecoder.decodeSymbolWithICDF(IcdfData.icdfPeriodicityIndex);

    for (int i = 0; i < SilkConstants.subframeCount; i++) {
      List<int> filterIndiceIcdf;
      switch (periodicityIndex) {
        case 0:
          filterIndiceIcdf = IcdfData.icdfLTPFilterIndex0;
          break;
        case 1:
          filterIndiceIcdf = IcdfData.icdfLTPFilterIndex1;
          break;
        case 2:
          filterIndiceIcdf = IcdfData.icdfLTPFilterIndex2;
          break;
      }

      final filterIndex = _rangeDecoder.decodeSymbolWithICDF(filterIndiceIcdf);
      List<List<int>> lTPFilterCodebook;

      switch (periodicityIndex) {
        case 0:
          lTPFilterCodebook = CodebookData.codebookLTPFilterPeriodicityIndex0;
          break;
        case 1:
          lTPFilterCodebook = CodebookData.codebookLTPFilterPeriodicityIndex1;
          break;
        case 2:
          lTPFilterCodebook = CodebookData.codebookLTPFilterPeriodicityIndex2;
          break;
      }
      bQ7[i].setAll(0, lTPFilterCodebook[filterIndex]);
    }
    return bQ7;
  }

  /// Returns the number of samples in a subframe based on bandwidth.
  /// Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.9
  int samplesInSubframe(Bandwidth bandwidth) {
    switch (bandwidth) {
      case Bandwidth.narrowband:
        return 40;
      case Bandwidth.mediumband:
        return 60;
      case Bandwidth.wideband:
        return 80;
    }
  }

  /// Performs LTP synthesis.
  /// Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.9.1
  void ltpSynthesis(
      List<double> out,
      List<List<int>> bQ7,
      List<int> pitchLags,
      int n,
      int j,
      int s,
      int dLPC,
      double LTPScaleQ14,
      int wQ2,
      List<double> aQ12,
      List<double> gainQ16,
      List<double> res,
      List<double> resLag) {
    int outEnd;
    if (s < 2 || wQ2 == 4) {
      outEnd = -s * n;
    } else {
      outEnd = -(s - 2) * n;
      LTPScaleQ14 = 16384.0;
    }

    for (int i = -pitchLags[s] - 2; i < outEnd; i++) {
      final index = i + j;
      double resVal;
      int resIndex;
      bool writeToLag = false;

      if (index >= res.length) {
        continue;
      } else if (index >= 0) {
        resVal = out[index];
        resIndex = index;
      } else {
        resIndex = resLag.length + index;
        resVal = finalOutValues[finalOutValues.length + index];
        writeToLag = true;
      }

      for (int k = 0; k < dLPC; k++) {
        double outVal;
        final outIndex = index - k - 1;
        if (outIndex >= 0) {
          outVal = out[outIndex];
        } else {
          outVal = finalOutValues[finalOutValues.length + outIndex];
        }
        resVal -= outVal * (aQ12[k] / 4096.0);
      }

      resVal = clampNegativeOneToOne(resVal);
      resVal *= (4.0 * LTPScaleQ14) / gainQ16[s];

      if (!writeToLag) {
        res[resIndex] = resVal;
      } else {
        resLag[resIndex] = resVal;
      }
    }

    if (s > 0) {
      final scaledGain = gainQ16[s - 1] / gainQ16[s];
      for (int i = outEnd; i < 0; i++) {
        final index = j + i;
        if (index < 0) {
          resLag[resLag.length + index] *= scaledGain;
        } else {
          res[index] *= scaledGain;
        }
      }
    }

    double resSum;
    double resVal;
    for (int i = j; i < (j + n); i++) {
      resSum = res[i];
      for (int k = 0; k <= 4; k++) {
        final resIndex = i - pitchLags[s] + 2 - k;
        if (resIndex < 0) {
          resVal = resLag[resLag.length + resIndex];
        } else {
          resVal = res[resIndex];
        }
        resSum += resVal * (bQ7[s][k] / 128.0);
      }
      res[i] = resSum;
    }
  }

  /// Performs LPC synthesis.
  /// Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.9.2
  void lpcSynthesis(
      List<double> out, int n, int s, int dLPC, List<double> aQ12, List<double> res, List<double> gainQ16, List<double> lpc) {
    final j = 0; // Relative to the start of the current subframe's residual segment.

    double currentLPCVal;
    for (int i = j; i < (j + n); i++) {
      final sampleIndex = i + (n * s);

      double lpcVal = gainQ16[s] / 65536.0;
      lpcVal *= res[sampleIndex];

      for (int k = 0; k < dLPC; k++) {
        final lpcIndex = sampleIndex - k - 1;
        if (lpcIndex >= 0) {
          currentLPCVal = lpc[lpcIndex];
        } else if (i < previousFrameLPCValues.length && s == 0) {
          // This logic in Go code `previousFrameLPCValues[len(previousFrameLPCValues)-1+(i-k)]`
          // seems to handle negative indices relative to end.
          // This needs to be careful. The Go code uses `i-k` on the *original* `i` which can be < 0 for first subframe.
          // So `len(previousFrameLPCValues)-1+(i-k)` would be `dLPC-1+(i-k)`
          final effectivePrevIndex = previousFrameLPCValues.length + lpcIndex;
          currentLPCVal = effectivePrevIndex >= 0 && effectivePrevIndex < previousFrameLPCValues.length
              ? previousFrameLPCValues[effectivePrevIndex]
              : 0; // Default to 0 if outside valid range
        } else {
          currentLPCVal = 0.0;
        }

        lpcVal += currentLPCVal * (aQ12[k] / 4096.0);
      }

      lpc[sampleIndex] = lpcVal;
      out[i] = clampNegativeOneToOne(lpc[sampleIndex]);

      if (i == (out.length - 1) && haveDecoded) {
        // Save the final dLPC values for the next frame
        previousFrameLPCValues = lpc.sublist(lpc.length - dLPC);
      }
    }
  }

  /// Reconstructs a SILK frame.
  /// Ref: https://www.rfc-editor.org/rfc/rfc6716.html#section-4.2.7.9
  void silkFrameReconstruction(
      FrameSignalType signalType,
      Bandwidth bandwidth,
      int dLPC,
      int lagMax,
      List<List<int>> bQ7,
      List<int> pitchLags,
      List<int> eQ23,
      double LTPScaleQ14,
      int wQ2,
      List<List<double>> aQ12,
      List<double> gainQ16,
      List<double> out) {
    final int n = samplesInSubframe(bandwidth); // samples in a subframe

    final lpc = List<double>.filled(n * SilkConstants.subframeCount, 0.0);

    final res = List<double>.filled(eQ23.length, 0.0);
    final resLag = List<double>.filled(lagMax + 2, 0.0);

    for (int i = 0; i < res.length; i++) {
      res[i] = eQ23[i] / 8388608.0; // 2.0**23
    }

    for (int subFrame = 0; subFrame < SilkConstants.subframeCount; subFrame++) {
      final int aQ12Index = (subFrame > 1 && aQ12.length > 1) ? 1 : 0;
      final int j = n * subFrame; // index of the first sample in the residual for current subframe.

      if (signalType == FrameSignalType.voiced) {
        ltpSynthesis(
          out,
          bQ7,
          pitchLags,
          n,
          j,
          subFrame,
          dLPC,
          LTPScaleQ14,
          wQ2,
          aQ12[aQ12Index],
          gainQ16,
          res,
          resLag,
        );
      }

      lpcSynthesis(
        out.sublist(n * subFrame, n * (subFrame + 1)),
        n,
        subFrame,
        dLPC,
        aQ12[aQ12Index],
        res,
        gainQ16,
        lpc,
      );
    }
  }

  /// Decodes many SILK subframes.
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.2.1
  SilkError? decode(List<int> input, List<double> output, bool isStereo, int nanoseconds, Bandwidth bandwidth) {
    final subframeSize = samplesInSubframe(bandwidth);
    if (nanoseconds != SilkConstants.nanoseconds20Ms) {
      return errUnsupportedSilkFrameDuration;
    }
    if (isStereo) {
      return errUnsupportedSilkStereo;
    }
    if ((subframeSize * SilkConstants.subframeCount) > output.length) {
      return errOutBufferTooSmall;
    }

    _rangeDecoder.init(input);

    final (voiceActivityDetected, lowBitRateRedundancy) = decodeHeaderBits();
    if (lowBitRateRedundancy) {
      return errUnsupportedSilkLowBitrateRedundancy;
    }

    final (signalType, quantizationOffsetType) = determineFrameType(voiceActivityDetected);

    final gainQ16 = decodeSubframeQuantizations(signalType);

    final I1 = normalizeLineSpectralFrequencyStageOne(signalType == FrameSignalType.voiced, bandwidth);

    final (dLPC, resQ10) = normalizeLineSpectralFrequencyStageTwo(bandwidth, I1);

    final nlsfQ15 = normalizeLineSpectralFrequencyCoefficients(dLPC, bandwidth, resQ10, I1);

    normalizeLSFStabilization(nlsfQ15, dLPC, bandwidth);

    final (n1Q15, wQ2) = normalizeLSFInterpolation(nlsfQ15);

    final aQ12 = <List<double>>[];
    generateAQ12(n1Q15, bandwidth, aQ12);
    generateAQ12(nlsfQ15, bandwidth, aQ12);

    final (lagMax, pitchLags, err) = decodePitchLags(signalType, bandwidth);
    if (err != null) {
      return err;
    }

    final bQ7 = decodeLTPFilterCoefficients(signalType);

    final LTPScaleQ14 = decodeLTPScalingParamater(signalType);

    final lcgSeed = decodeLinearCongruentialGeneratorSeed();

    final shellblocks = decodeShellblocks(nanoseconds, bandwidth);

    final rateLevel = decodeRatelevel(signalType == FrameSignalType.voiced);

    final (pulsecounts, lsbcounts) = decodePulseAndLSBCounts(shellblocks, rateLevel);

    final eQ23 = decodeExcitation(signalType, quantizationOffsetType, lcgSeed, pulsecounts, lsbcounts);

    silkFrameReconstruction(
      signalType,
      bandwidth,
      dLPC,
      lagMax,
      bQ7,
      pitchLags!, // pitchLags is guaranteed to be non-null if signalType is voiced
      eQ23,
      LTPScaleQ14,
      wQ2,
      aQ12,
      gainQ16,
      output,
    );

    isPreviousFrameVoiced = signalType == FrameSignalType.voiced;

    if (n0Q15.length != nlsfQ15.length) {
      n0Q15 = List<int>.filled(nlsfQ15.length, 0);
    }
    n0Q15.setAll(0, nlsfQ15);

    // Save the final values of out
    finalOutValues.setAll(0, output.sublist(output.length - finalOutValues.length));

    haveDecoded = true;

    return null; // No error
  }
}