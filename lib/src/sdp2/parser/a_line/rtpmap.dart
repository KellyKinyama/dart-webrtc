import '../../interface.dart';

rtpmapParser (SdpAVMediaSection section, String line){
  final lineParts = line.split(' ');
  final payloadType = int.parse(lineParts[0]);
  const fmtSection = section.fmt?.find(fmtp=>fmtp.payloadType === payloadType);
  if(fmtSection){
    fmtSection.contentType = lineParts[1];
  }
}