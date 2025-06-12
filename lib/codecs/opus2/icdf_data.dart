// SPDX-FileCopyrightText: 2023 The Pion community <https://pion.ly>
// SPDX-License-Identifier: MIT

// Package silk provides Inverse Cumulative Distribution Function (ICDF) tables.

// All ICDF tables are represented as List<int>.
// The first element is the total count, followed by cumulative frequencies.
// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-4.1.3.3

class IcdfData {
  static const List<int> icdfFrameTypeVADInactive = [256, 26, 256];
  static const List<int> icdfFrameTypeVADActive = [256, 24, 98, 246, 256];

  static const List<int> icdfIndependentQuantizationGainMSBInactive = [
    256,
    32,
    144,
    212,
    241,
    253,
    254,
    255,
    256
  ];
  static const List<int> icdfIndependentQuantizationGainMSBUnvoiced = [
    256,
    2,
    19,
    64,
    124,
    186,
    233,
    252,
    256
  ];
  static const List<int> icdfIndependentQuantizationGainMSBVoiced = [
    256,
    1,
    4,
    30,
    101,
    195,
    245,
    254,
    256
  ];

  static const List<int> icdfIndependentQuantizationGainLSB = [
    256,
    32,
    64,
    96,
    128,
    160,
    192,
    224,
    256
  ];

  static const List<int> icdfDeltaQuantizationGain = [
    256,
    6,
    11,
    22,
    53,
    185,
    206,
    214,
    218,
    221,
    223,
    225,
    227,
    228,
    229,
    230,
    231,
    232,
    233,
    234,
    235,
    236,
    237,
    238,
    239,
    240,
    241,
    242,
    243,
    244,
    245,
    246,
    247,
    248,
    249,
    250,
    251,
    252,
    253,
    254,
    255,
    256,
  ];

  static const List<int>
      icdfNormalizedLSFStageOneIndexNarrowbandOrMediumbandUnvoiced = [
    256,
    44,
    78,
    108,
    127,
    148,
    160,
    171,
    174,
    177,
    179,
    195,
    197,
    199,
    200,
    205,
    207,
    208,
    211,
    214,
    215,
    216,
    218,
    220,
    222,
    225,
    226,
    235,
    244,
    246,
    253,
    255,
    256,
  ];
  static const List<int>
      icdfNormalizedLSFStageOneIndexNarrowbandOrMediumbandVoiced = [
    256,
    1,
    11,
    12,
    20,
    23,
    31,
    39,
    53,
    66,
    80,
    81,
    95,
    107,
    120,
    131,
    142,
    154,
    165,
    175,
    185,
    196,
    204,
    213,
    221,
    228,
    236,
    237,
    238,
    244,
    245,
    251,
    256,
  ];
  static const List<int> icdfNormalizedLSFStageOneIndexWidebandUnvoiced = [
    256,
    31,
    52,
    55,
    72,
    73,
    81,
    98,
    102,
    103,
    121,
    137,
    141,
    143,
    146,
    147,
    157,
    158,
    161,
    177,
    188,
    204,
    206,
    208,
    211,
    213,
    224,
    225,
    229,
    238,
    246,
    253,
    256,
  ];
  static const List<int> icdfNormalizedLSFStageOneIndexWidebandVoiced = [
    256,
    1,
    5,
    21,
    26,
    44,
    55,
    60,
    74,
    89,
    90,
    93,
    105,
    118,
    132,
    146,
    152,
    166,
    178,
    180,
    186,
    187,
    199,
    211,
    222,
    232,
    235,
    245,
    250,
    251,
    252,
    253,
    256,
  ];

  static const List<int> icdfNormalizedLSFStageTwoIndexExtension = [
    256,
    156,
    216,
    240,
    249,
    253,
    255,
    256
  ];

  // NB/MD and WD ICDF are combined because the codebooks do not overlap.
  static const List<List<int>> icdfNormalizedLSFStageTwoIndex = [
    // Narrowband and Mediumband
    [256, 1, 2, 3, 18, 242, 253, 254, 255, 256], // 'a'
    [256, 1, 2, 4, 38, 221, 253, 254, 255, 256], // 'b'
    [256, 1, 2, 6, 48, 197, 252, 254, 255, 256], // 'c'
    [256, 1, 2, 10, 62, 185, 246, 254, 255, 256], // 'd'
    [256, 1, 4, 20, 73, 174, 248, 254, 255, 256], // 'e'
    [256, 1, 4, 21, 76, 166, 239, 254, 255, 256], // 'f'
    [256, 1, 8, 32, 85, 159, 226, 252, 255, 256], // 'g'
    [256, 1, 2, 20, 83, 161, 219, 249, 255, 256], // 'h'

    // Wideband
    [256, 1, 2, 3, 12, 244, 253, 254, 255, 256], // 'i'
    [256, 1, 2, 4, 32, 218, 253, 254, 255, 256], // 'j'
    [256, 1, 2, 5, 47, 199, 252, 254, 255, 256], // 'k'
    [256, 1, 2, 12, 61, 187, 252, 254, 255, 256], // 'l'
    [256, 1, 5, 24, 72, 172, 249, 254, 255, 256], // 'm'
    [256, 1, 2, 16, 70, 170, 242, 254, 255, 256], // 'n'
    [256, 1, 2, 17, 78, 165, 226, 251, 255, 256], // 'o'
    [256, 1, 8, 29, 79, 156, 237, 254, 255, 256], // 'p'
  ];

  static const List<int> icdfNormalizedLSFInterpolationIndex = [
    256,
    13,
    35,
    64,
    75,
    256,
  ];

  static const List<int> icdfLinearCongruentialGeneratorSeed = [
    256,
    64,
    128,
    192,
    256,
  ];

  static const List<int> icdfRateLevelUnvoiced = [
    256,
    15,
    66,
    78,
    124,
    169,
    182,
    215,
    242,
    256
  ];
  static const List<int> icdfRateLevelVoiced = [
    256,
    33,
    63,
    99,
    116,
    150,
    199,
    217,
    238,
    256
  ];

  static const List<List<int>> icdfPulseCount = [
    [
      256,
      131,
      205,
      230,
      238,
      241,
      244,
      245,
      246,
      247,
      248,
      249,
      250,
      251,
      252,
      253,
      254,
      255,
      256
    ],
    [
      256,
      58,
      151,
      211,
      234,
      241,
      244,
      245,
      246,
      247,
      248,
      249,
      250,
      251,
      252,
      253,
      254,
      255,
      256
    ],
    [
      256,
      43,
      94,
      140,
      173,
      197,
      213,
      224,
      232,
      238,
      241,
      244,
      247,
      249,
      250,
      251,
      253,
      254,
      256
    ],
    [
      256,
      17,
      69,
      140,
      197,
      228,
      240,
      245,
      246,
      247,
      248,
      249,
      250,
      251,
      252,
      253,
      254,
      255,
      256
    ],
    [
      256,
      6,
      27,
      68,
      121,
      170,
      205,
      226,
      237,
      243,
      246,
      248,
      250,
      251,
      252,
      253,
      254,
      255,
      256
    ],
    [
      256,
      7,
      21,
      43,
      71,
      100,
      128,
      153,
      173,
      190,
      203,
      214,
      223,
      230,
      235,
      239,
      243,
      246,
      256
    ],
    [
      256,
      2,
      7,
      21,
      50,
      92,
      138,
      179,
      210,
      229,
      240,
      246,
      249,
      251,
      252,
      253,
      254,
      255,
      256
    ],
    [
      256,
      1,
      3,
      7,
      17,
      36,
      65,
      100,
      137,
      171,
      199,
      219,
      233,
      241,
      246,
      250,
      252,
      254,
      256
    ],
    [
      256,
      1,
      3,
      5,
      10,
      19,
      33,
      53,
      77,
      104,
      132,
      158,
      181,
      201,
      216,
      227,
      235,
      241,
      256
    ],
    [
      256,
      1,
      2,
      3,
      9,
      36,
      94,
      150,
      189,
      214,
      228,
      238,
      244,
      247,
      250,
      252,
      253,
      254,
      256
    ],
    [
      256,
      2,
      3,
      9,
      36,
      94,
      150,
      189,
      214,
      228,
      238,
      244,
      247,
      250,
      252,
      253,
      254,
      256,
      256
    ],
  ];

  static const List<List<int>> icdfPulseCountSplit16SamplePartitions = [
    [256, 126, 256],
    [256, 56, 198, 256],
    [256, 25, 126, 230, 256],
    [256, 12, 72, 180, 244, 256],
    [256, 7, 42, 126, 213, 250, 256],
    [256, 4, 24, 83, 169, 232, 253, 256],
    [256, 3, 15, 53, 125, 200, 242, 254, 256],
    [256, 2, 10, 35, 89, 162, 221, 248, 255, 256],
    [256, 2, 7, 24, 63, 126, 191, 233, 251, 255, 256],
    [256, 1, 5, 17, 45, 94, 157, 211, 241, 252, 255, 256],
    [256, 1, 5, 13, 33, 70, 125, 182, 223, 245, 253, 255, 256],
    [256, 1, 4, 11, 26, 54, 98, 151, 199, 232, 248, 254, 255, 256],
    [256, 1, 3, 9, 21, 42, 77, 124, 172, 212, 237, 249, 254, 255, 256],
    [256, 1, 2, 6, 16, 33, 60, 97, 144, 187, 220, 241, 250, 254, 255, 256],
    [256, 1, 2, 3, 11, 25, 47, 80, 120, 163, 201, 229, 245, 253, 254, 255, 256],
    [
      256,
      1,
      2,
      3,
      4,
      17,
      35,
      62,
      98,
      139,
      180,
      214,
      238,
      252,
      253,
      254,
      255,
      256
    ],
  ];

  static const List<List<int>> icdfPulseCountSplit8SamplePartitions = [
    [256, 127, 256],
    [256, 53, 202, 256],
    [256, 22, 127, 233, 256],
    [256, 11, 72, 183, 246, 256],
    [256, 6, 41, 127, 215, 251, 256],
    [256, 4, 24, 83, 170, 232, 253, 256],
    [256, 3, 16, 56, 127, 200, 241, 254, 256],
    [256, 3, 12, 39, 92, 162, 218, 246, 255, 256],
    [256, 3, 11, 30, 67, 124, 185, 229, 249, 255, 256],
    [256, 3, 10, 25, 53, 97, 151, 200, 233, 250, 255, 256],
    [256, 1, 8, 21, 43, 77, 123, 171, 209, 237, 251, 255, 256],
    [256, 1, 2, 13, 35, 62, 97, 139, 186, 219, 244, 254, 255, 256],
    [256, 1, 2, 8, 22, 48, 85, 128, 171, 208, 234, 248, 254, 255, 256],
    [256, 1, 2, 6, 16, 36, 67, 107, 149, 189, 220, 240, 250, 254, 255, 256],
    [256, 1, 2, 5, 13, 29, 55, 90, 128, 166, 201, 227, 243, 251, 254, 255, 256],
    [
      256,
      1,
      2,
      4,
      10,
      22,
      43,
      73,
      109,
      147,
      183,
      213,
      234,
      246,
      252,
      254,
      255,
      256
    ],
  ];

  static const List<List<int>> icdfPulseCountSplit4SamplePartitions = [
    [256, 127, 256],
    [256, 49, 206, 256],
    [256, 20, 127, 236, 256],
    [256, 11, 71, 184, 246, 256],
    [256, 7, 43, 127, 214, 250, 256],
    [256, 6, 30, 87, 169, 229, 252, 256],
    [256, 5, 23, 62, 126, 194, 236, 252, 256],
    [256, 6, 20, 49, 96, 157, 209, 239, 253, 256],
    [256, 1, 16, 39, 74, 125, 175, 215, 245, 255, 256],
    [256, 1, 2, 23, 55, 97, 149, 195, 236, 254, 255, 256],
    [256, 1, 7, 23, 50, 86, 128, 170, 206, 233, 249, 255, 256],
    [256, 1, 6, 18, 39, 70, 108, 148, 186, 217, 238, 250, 255, 256],
    [256, 1, 4, 13, 30, 56, 90, 128, 166, 200, 226, 243, 252, 255, 256],
    [256, 1, 4, 11, 25, 47, 76, 110, 146, 180, 209, 231, 245, 252, 255, 256],
    [256, 1, 3, 8, 19, 37, 62, 93, 128, 163, 194, 219, 237, 248, 253, 255, 256],
    [
      256,
      1,
      2,
      6,
      15,
      30,
      51,
      79,
      111,
      145,
      177,
      205,
      226,
      241,
      250,
      254,
      255,
      256
    ],
  ];

  static const List<List<int>> icdfPulseCountSplit2SamplePartitions = [
    [256, 128, 256],
    [256, 42, 214, 256],
    [256, 21, 128, 235, 256],
    [256, 12, 72, 184, 245, 256],
    [256, 8, 42, 128, 214, 249, 256],
    [256, 8, 31, 86, 176, 231, 251, 256],
    [256, 5, 20, 58, 130, 202, 238, 253, 256],
    [256, 6, 18, 45, 97, 174, 221, 241, 251, 256],
    [256, 6, 25, 53, 88, 128, 168, 203, 231, 250, 256],
    [256, 4, 18, 40, 71, 108, 148, 185, 216, 238, 252, 256],
    [256, 3, 13, 31, 57, 90, 128, 166, 199, 225, 243, 253, 256],
    [256, 2, 10, 23, 44, 73, 109, 147, 183, 212, 233, 246, 254, 256],
    [256, 1, 6, 16, 33, 58, 90, 128, 166, 198, 223, 240, 250, 255, 256],
    [256, 1, 5, 12, 25, 46, 75, 110, 146, 181, 210, 231, 244, 251, 255, 256],
    [256, 1, 3, 8, 18, 35, 60, 92, 128, 164, 196, 221, 238, 248, 253, 255, 256],
    [
      256,
      1,
      3,
      7,
      14,
      27,
      48,
      76,
      110,
      146,
      180,
      208,
      229,
      242,
      249,
      253,
      255,
      256
    ],
  ];

  static const List<int> icdfExcitationLSB = [256, 136, 256];

  // Excitation sign ICDFs: Grouped by SignalType, QuantizationOffsetType, and PulseCount
  static const List<int> icdfExcitationSignInactiveSignalLowQuantization0Pulse =
      [256, 2, 256];
  static const List<int> icdfExcitationSignInactiveSignalLowQuantization1Pulse =
      [256, 207, 256];
  static const List<int> icdfExcitationSignInactiveSignalLowQuantization2Pulse =
      [256, 189, 256];
  static const List<int> icdfExcitationSignInactiveSignalLowQuantization3Pulse =
      [256, 179, 256];
  static const List<int> icdfExcitationSignInactiveSignalLowQuantization4Pulse =
      [256, 174, 256];
  static const List<int> icdfExcitationSignInactiveSignalLowQuantization5Pulse =
      [256, 163, 256];
  static const List<int>
      icdfExcitationSignInactiveSignalLowQuantization6PlusPulse =
      [256, 157, 256];

  static const List<int>
      icdfExcitationSignInactiveSignalHighQuantization0Pulse = [256, 58, 256];
  static const List<int>
      icdfExcitationSignInactiveSignalHighQuantization1Pulse = [256, 245, 256];
  static const List<int>
      icdfExcitationSignInactiveSignalHighQuantization2Pulse = [256, 238, 256];
  static const List<int>
      icdfExcitationSignInactiveSignalHighQuantization3Pulse = [256, 232, 256];
  static const List<int>
      icdfExcitationSignInactiveSignalHighQuantization4Pulse = [256, 225, 256];
  static const List<int>
      icdfExcitationSignInactiveSignalHighQuantization5Pulse = [256, 220, 256];
  static const List<int>
      icdfExcitationSignInactiveSignalHighQuantization6PlusPulse =
      [256, 211, 256];

  static const List<int> icdfExcitationSignUnvoicedSignalLowQuantization0Pulse =
      [256, 1, 256];
  static const List<int> icdfExcitationSignUnvoicedSignalLowQuantization1Pulse =
      [256, 210, 256];
  static const List<int> icdfExcitationSignUnvoicedSignalLowQuantization2Pulse =
      [256, 190, 256];
  static const List<int> icdfExcitationSignUnvoicedSignalLowQuantization3Pulse =
      [256, 178, 256];
  static const List<int> icdfExcitationSignUnvoicedSignalLowQuantization4Pulse =
      [256, 169, 256];
  static const List<int> icdfExcitationSignUnvoicedSignalLowQuantization5Pulse =
      [256, 162, 256];
  static const List<int>
      icdfExcitationSignUnvoicedSignalLowQuantization6PlusPulse =
      [256, 152, 256];

  static const List<int>
      icdfExcitationSignUnvoicedSignalHighQuantization0Pulse = [256, 48, 256];
  static const List<int>
      icdfExcitationSignUnvoicedSignalHighQuantization1Pulse = [256, 242, 256];
  static const List<int>
      icdfExcitationSignUnvoicedSignalHighQuantization2Pulse = [256, 235, 256];
  static const List<int>
      icdfExcitationSignUnvoicedSignalHighQuantization3Pulse = [256, 224, 256];
  static const List<int>
      icdfExcitationSignUnvoicedSignalHighQuantization4Pulse = [256, 214, 256];
  static const List<int>
      icdfExcitationSignUnvoicedSignalHighQuantization5Pulse = [256, 205, 256];
  static const List<int>
      icdfExcitationSignUnvoicedSignalHighQuantization6PlusPulse =
      [256, 190, 256];

  static const List<int> icdfExcitationSignVoicedSignalLowQuantization0Pulse =
      [256, 1, 256];
  static const List<int> icdfExcitationSignVoicedSignalLowQuantization1Pulse =
      [256, 162, 256];
  static const List<int> icdfExcitationSignVoicedSignalLowQuantization2Pulse =
      [256, 152, 256];
  static const List<int> icdfExcitationSignVoicedSignalLowQuantization3Pulse =
      [256, 147, 256];
  static const List<int> icdfExcitationSignVoicedSignalLowQuantization4Pulse =
      [256, 144, 256];
  static const List<int> icdfExcitationSignVoicedSignalLowQuantization5Pulse =
      [256, 141, 256];
  static const List<int>
      icdfExcitationSignVoicedSignalLowQuantization6PlusPulse =
      [256, 138, 256];

  static const List<int> icdfExcitationSignVoicedSignalHighQuantization0Pulse =
      [256, 8, 256];
  static const List<int> icdfExcitationSignVoicedSignalHighQuantization1Pulse =
      [256, 203, 256];
  static const List<int> icdfExcitationSignVoicedSignalHighQuantization2Pulse =
      [256, 187, 256];
  static const List<int> icdfExcitationSignVoicedSignalHighQuantization3Pulse =
      [256, 176, 256];
  static const List<int> icdfExcitationSignVoicedSignalHighQuantization4Pulse =
      [256, 168, 256];
  static const List<int> icdfExcitationSignVoicedSignalHighQuantization5Pulse =
      [256, 161, 256];
  static const List<int>
      icdfExcitationSignVoicedSignalHighQuantization6PlusPulse =
      [256, 154, 256];

  static const List<int> icdfPrimaryPitchLagHighPart = [
    256,
    3,
    6,
    12,
    23,
    44,
    74,
    106,
    125,
    136,
    146,
    158,
    171,
    184,
    196,
    207,
    216,
    224,
    231,
    237,
    241,
    243,
    245,
    247,
    248,
    249,
    250,
    251,
    252,
    253,
    254,
    255,
    256,
  ];

  static const List<int> icdfPrimaryPitchLagLowPartNarrowband = [
    256,
    64,
    128,
    192,
    256
  ];
  static const List<int> icdfPrimaryPitchLagLowPartMediumband = [
    256,
    43,
    85,
    128,
    171,
    213,
    256
  ];
  static const List<int> icdfPrimaryPitchLagLowPartWideband = [
    256,
    32,
    64,
    96,
    128,
    160,
    192,
    224,
    256
  ];

  static const List<int> icdfSubframePitchContourNarrowband10Ms = [
    256,
    143,
    193,
    256,
  ];
  static const List<int> icdfSubframePitchContourNarrowband20Ms = [
    256,
    68,
    80,
    101,
    118,
    137,
    159,
    189,
    213,
    230,
    246,
    256,
  ];
  static const List<int> icdfSubframePitchContourMediumbandOrWideband10Ms = [
    256,
    91,
    137,
    176,
    195,
    209,
    221,
    229,
    236,
    242,
    247,
    252,
    256,
  ];
  static const List<int> icdfSubframePitchContourMediumbandOrWideband20Ms = [
    256,
    33,
    55,
    73,
    89,
    104,
    118,
    132,
    145,
    158,
    168,
    177,
    186,
    194,
    200,
    206,
    212,
    217,
    221,
    225,
    229,
    232,
    235,
    238,
    240,
    242,
    244,
    246,
    248,
    250,
    252,
    253,
    254,
    255,
    256,
  ];

  static const List<int> icdfPeriodicityIndex = [256, 77, 157, 256];

  static const List<int> icdfLTPFilterIndex0 = [
    256,
    185,
    200,
    213,
    226,
    235,
    244,
    250,
    256,
  ];
  static const List<int> icdfLTPFilterIndex1 = [
    256,
    57,
    91,
    112,
    132,
    147,
    160,
    172,
    185,
    195,
    205,
    214,
    224,
    233,
    241,
    248,
    256,
  ];
  static const List<int> icdfLTPFilterIndex2 = [
    256,
    15,
    31,
    45,
    57,
    69,
    81,
    92,
    103,
    114,
    124,
    133,
    142,
    151,
    160,
    168,
    176,
    184,
    192,
    199,
    206,
    212,
    218,
    223,
    227,
    232,
    236,
    240,
    244,
    247,
    251,
    254,
    256,
  ];

  static const List<int> icdfLTPScalingParameter = [256, 128, 192, 256];
}