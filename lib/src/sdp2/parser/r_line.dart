// import {SdpRepeatTimes} from "../../../inerfaces/Sdp";
// import {linePartsParser} from "./line-parts.parser";
// import {lineTimeParser} from "./line-time.parser";

import '../interface.dart';
import 'line_parts.dart';
import 'line_time.dart';

SdpRepeatTimes rLineParser(String line) {
  final repeatParts = linePartsParser(line, 'r');
  final repeatInterval = lineTimeParser(repeatParts[0]);
  final activeDuration = lineTimeParser(repeatParts[0]);
  final sdpRepeatTimes=SdpRepeatTimes = {
    repeatInterval,
    activeDuration
  }
  if (repeatParts.length > 3) {
    sdpRepeatTimes.offsets = [];
    for (int i = 2; i < repeatParts.length; i++) {
      sdpRepeatTimes.offsets.push(lineTimeParser(repeatParts[i]));
    }
  }
  return sdpRepeatTimes;
}