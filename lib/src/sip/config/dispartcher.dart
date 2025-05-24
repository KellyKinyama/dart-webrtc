import '../sip_parser/sip.dart';

enum Status { ONLINE, OFFLINE }

List<int> dispatcherIps = [];

class Dispatcher {
  Dispatcher(this.id, this.transport);
  String id;
  sockaddr_in transport;
  Status state = Status.OFFLINE;
}

Map<int, Dispatcher> dispatcherList = {};

void initDispatcher() {
  dispatcherIps = [];
  dispatcherList[0] = Dispatcher('0', sockaddr_in("10.43.0.55", 5080, 'udp'));
  //dispatcherList[1] = Dispatcher('1', sockaddr_in("10.44.0.55", 5060, 'udp'));
  dispatcherIps.add(0);
  //dispatcherIps.add(1);
}
