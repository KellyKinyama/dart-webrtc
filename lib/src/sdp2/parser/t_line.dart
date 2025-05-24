import "../interface.dart";

// import {SdpTiming} from "../../../inerfaces/Sdp";
// import 
import "line_parts.dart";
// {linePartsParser} from "./line-parts.parser";

SdpTiming tLineParser (String line){
  final timingParts = linePartsParser(line,'t');
  final startTimeInt = parseInt(timingParts[0]);
  final startTime = isNaN(startTimeInt)?0:startTimeInt;
  final stopTimeInt = parseInt(timingParts[1]);
  final stopTime = isNaN(stopTimeInt)?0:stopTimeInt;
  return {
    startTime,
    stopTime
  }
}