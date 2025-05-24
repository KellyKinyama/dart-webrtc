

import '../interface.dart';
import 'line_parts.dart';

SdpOrigin oLineParser(String line) {
 final originParts = linePartsParser(line,'o');
 final sessVersion = int.parse(originParts[2]);
 final netType = originParts[3] == 'IN'?'IN':void 0;
 final addrType = ['IP4','IP6'].includes(originParts[4])?originParts[4] as 'IP4'|'IP6':void 0;
 return {
  username: originParts[0],
  sessId: originParts[1],
  sessVersion,
  netType,
  addrType,
  unicastAddress: originParts[5]
 }
}