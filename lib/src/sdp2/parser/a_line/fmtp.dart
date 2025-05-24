import '../../interface.dart';

fmtpParser (SdpAVMediaSection section, String line){
  final lineParts = line.split(' ');
  final payloadType = int.parse(lineParts[0]);
  final fmtSection = section.fmt?.find(fmtp=>fmtp.payloadType == payloadType);
  if(fmtSection){
    if(!fmtSection.formatParameters){
      fmtSection.formatParameters = {};
    }
    const params = lineParts[1].split(';').map(paramValue=>paramValue.split('='));
    for(const param of params){
      fmtSection.formatParameters[param[0]] = (typeof param[1] !=='undefined')?param[1] : 'unknown';
    }
  }
}