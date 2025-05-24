
import '../interface.dart';
import 'line_parts.dart';

SdpConnectionInformation cLineParser (String line){
  final lineParts = linePartsParser(line,'c');
  const netType = lineParts[0] === 'IN'?'IN':void 0;
  const addrType = ['IP4','IP6'].includes(lineParts[1])?lineParts[1] as 'IP4'|'IP6':void 0;
  return {
    netType,
    addrType,
    connectionAddress: lineParts[2]
  }
}