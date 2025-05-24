import '../interface.dart';
import 'string_to_int.dart';

SdpBandwidthInformation bLineParser(String line) {
  final lineContent = line.replaceFirst('k=', '');
  final [bwtype, bandwidth] = lineContent.split(':');
  return SdpBandwidthInformation(bwtype,
      bandwidth: stringToIntParser(bandwidth));
}
