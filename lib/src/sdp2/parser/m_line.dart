// import {SdpAppMediaSection, SdpAVMediaSection, SdpMediaSection, SdpOtherMediaSection} from "../../../inerfaces/Sdp";
// import {linePartsParser} from "./line-parts.parser";

import '../interface.dart';
import 'line_parts.dart';

List<num> parsePorts (String ports) {
  return ports.split('/').map(str => int.parse(str));
}

SdpAVMediaSection avLineParser (List<String> mediaParts){
  SdpAVMediaSection section= SdpAVMediaSection = {
    type: mediaParts[0] as 'audio' | 'video',
    ports: parsePorts(mediaParts[1]),
    proto: mediaParts[2],
  }
  if (mediaParts.length > 3) {
    section.fmt = [];
    for (let i = 3; i < mediaParts.length; i++) {
      section.fmt.push({ payloadType: parseInt(mediaParts[i])});
    }
  }
  return section;
}
SdpAppMediaSection appLineParser (List<String> mediaParts) {
  return {
    type: 'application',
    ports: parsePorts(mediaParts[1]),
    proto: mediaParts[2],
    description: mediaParts[3]
  } as SdpAppMediaSection;
}
SdpOtherMediaSection unknownLineParser(List<String> mediaParts) {
  SdpOtherMediaSection section= SdpOtherMediaSection {
    type: mediaParts[0],
    ports: parsePorts(mediaParts[1]),
    proto: mediaParts[2],
  }
  if (mediaParts.length > 3) {
    section.fmtp = [];
    for (let i = 3; i < mediaParts.length; i++) {
      section.fmtp.push(mediaParts[i]);
    }
  }
  return section;
}

SdpMediaSection mLineParser(String line) {
  final mediaParts = linePartsParser(line, 'm');
  switch (mediaParts[0]) {
    case 'audio':
      return avLineParser(mediaParts);
    case 'video':
      return avLineParser(mediaParts);
    case 'application':
      return appLineParser(mediaParts);
    default:
      return unknownLineParser(mediaParts);
  }
}