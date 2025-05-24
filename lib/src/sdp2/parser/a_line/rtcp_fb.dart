 import '../../interface.dart';

rtcpFbParser (SdpAVMediaSection section, String line){
  final lineParts = line.split(' ');
  final payloadType = int.parse(lineParts[0]);
  const fmtpSection = section.fmt?.find(fmtp=>fmtp.payloadType === payloadType);
  if(fmtpSection){
    if(!fmtpSection.rtcpFeedback){
      fmtpSection.rtcpFeedback = [];
    }
    fmtpSection.rtcpFeedback.push(lineParts[1]);
  }
}