import '../../interface.dart';

extmapParser (SdpMediaSection section, String line){
  if(!section.extmap){
    section.extmap = {};
  }
  final lineParts = line.split(' ');
  section.extmap[int.parse(lineParts[0])] = lineParts[1];
}