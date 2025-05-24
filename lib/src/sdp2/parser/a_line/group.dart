
import '../../interface.dart';

groupParser(Sdp sectionp, String value){
  if(!section.group){
    section.group = [];
  }
  final [token,...mids] = value.split(' ');
  final availableTokens=SdpGroup["token"][] = ['LS','FID','SRF','ANAT','FEC','DDP','BUNDLE'];
  if(availableTokens.includes(token as SdpGroup["token"])) {
    section.group.push({
      token: token as SdpGroup["token"],
      mids
    })
  }
  // else ignore unknown group;
}