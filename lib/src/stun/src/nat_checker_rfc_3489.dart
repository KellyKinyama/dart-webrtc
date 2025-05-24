import 'dart:io';

import '../stun.dart';

/// NAT的行为类型和侦测方法是由STUN（首先在RFC3489中定义，英文全称是Simple Traversal of UDP Through NATs）协议来描述的，STUN协议包括了RFC3489、RFC5389、RFC5780、RFC5769几个系列文档。
///
/// 早期的STUN协议是由RFC3489（经典的STUN）来描述，其定义的NAT行为类型如下：
///
/// 1）Full Cone NAT - 完全锥形NAT：
/// 所有从同一个内网IP和端口号Endpoint1发送过来的请求都会被映射成同一个外网IP和端口号Endpoint2，并且任何一个外网主机都可以通过这个映射的Endpoint2向这台内网主机发送包。也就是外网所有发往Endpoint2的数据包都会被NAT转发给Endpoint1。由于对外部请求的来源无任何限制，因此这种方式虽然足够简单，但却不安全。
///
/// 2）Restricted Cone NAT - 限制锥形NAT：
/// 它是Full Cone的受限版本：所有来自同一个内网Endpoint1的请求均被NAT映射成同一个外网Endpoint2，这与Full Cone相同。但不同的是，只有当内网Endpoint1曾经发送过报文给外部主机（假设其IP地址为IP3）后，外部主机IP3发往Endpoint2的数据包才会被NAT转发给Endpoint1。这意味着，NAT设备只向内转发那些来自于当前已知的外部主机的数据包，从而保障了外部请求来源的安全性
///
/// 3）Port Restricted Cone NAT - 端口限制锥形NAT：
/// 它是Restricted Cone NAT的进一步受限版，与限制锥形NAT很相似，只不过它包括端口号PORT。只有当内网Endpoint1曾经发送过报文给外部Endpoint3(包括IP和端口了)，Endpoint3发往Endpoint2的数据包才会被NAT转发给Endpoint1。端口号PORT这一要求进一步强化了对外部报文请求来源的限制，从而较Restrictd Cone更具安全性。
///
/// 4）Symmetric NAT - 对称NAT：
/// 上面的1）2）3）所有的Cone NAT中，映射关系只和内网的源Endpoint1相关，只要源Endpoint1不变其都会被映射成同一个Endpoint2。而对称NAT的映射关系不只与源Endpoint1相关，还与目的Endpoint3相关。也就是源Endpoint1发往目的Endpoint30的请求被映射为Endpoint20，而源Endpoint1发往目的Endpoint31的请求，则被映射为Endpoint21了。此外，只有收到过内网主机发送的数据的外网主机才可以反过来向内网主机发送数据包。
///
/// 经典 STUN 定义的 NAT 行为类型是将NAT的Mapping Behavior （映射规则）和Filtering Behavior（过滤规则）统一来归类的，这样对Symmetric NAT类型的归类过于笼统，使得许多 NAT 不完全符合由它定义的类型。
///
/// 于是后来，RFC3489被废弃并由RFC5389来替代，在RFC5389中，将Mapping Behavior （映射规则）和Filtering Behavior（过滤规则）分开来，定义了3种Mapping Behavior （映射规则）和3种Filtering Behavior（过滤规则），一共有9种组合。
///
/// 为什么是3种呢？其实理由很简单，对于一个特定的内网源Endpoint1，影响其映射关系的因素不外乎就4种情况：
///
///     1）目的IP和目的端口PORT都无关；
///     2）目的IP和目的端口PORT都相关；
///     3）仅仅目的IP相关；
///     4）仅仅目的PORT相关。
///
///
/// 对于4仅仅考虑一下PORT信息有点鸡肋，基本和1差不多，于是把4去掉了。同样，对于过滤规则也一样。
enum NatBehavior {
  FullConeNat,
  RestrictedConeNat,
  PortRestrictedConeNat,
  SymmetricNat,
}

// 10.2 Binding Lifetime Discovery
//
//    STUN can also be used to discover the lifetimes of the bindings
//    created by the NAT.  In many cases, the client will need to refresh
//    the binding, either through a new STUN request, or an application
//    packet, in order for the application to continue to use the binding.
//    By discovering the binding lifetime, the client can determine how
//    frequently it needs to refresh.
//
//
//                         +--------+
//                         |  Test  |
//                         |   I    |
//                         +--------+
//                              |
//                              |
//                              V
//                             /\              /\
//                          N /  \ Y          /  \ Y             +--------+
//           UDP     <-------/Resp\--------->/ IP \------------->|  Test  |
//           Blocked         \ ?  /          \Same/              |   II   |
//                            \  /            \? /               +--------+
//                             \/              \/                    |
//                                              | N                  |
//                                              |                    V
//                                              V                    /\
//                                          +--------+  Sym.      N /  \
//                                          |  Test  |  UDP    <---/Resp\
//                                          |   II   |  Firewall   \ ?  /
//                                          +--------+              \  /
//                                              |                    \/
//                                              V                     |Y
//                   /\                         /\                    |
//    Symmetric  N  /  \       +--------+   N  /  \                   V
//       NAT  <--- / IP \<-----|  Test  |<--- /Resp\               Open
//                 \Same/      |   I    |     \ ?  /               Internet
//                  \? /       +--------+      \  /
//                   \/                         \/
//                   |                           |Y
//                   |                           |
//                   |                           V
//                   |                           Full
//                   |                           Cone
//                   V              /\
//               +--------+        /  \ Y
//               |  Test  |------>/Resp\---->Restricted
//               |   III  |       \ ?  /
//               +--------+        \  /
//                                  \/
//                                   |N
//                                   |       Port
//                                   +------>Restricted
//
//                  Figure 2: Flow for type discovery process
//
//    To determine the binding lifetime, the client first sends a Binding
//    Request to the server from a particular socket, X.  This creates a
//    binding in the NAT.  The response from the server contains a MAPPED-
//    ADDRESS attribute, providing the public address and port on the NAT.
//    Call this Pa and Pp, respectively.  The client then starts a timer
//    with a value of T seconds.  When this timer fires, the client sends
//    another Binding Request to the server, using the same destination
//    address and port, but from a different socket, Y.  This request
//    contains a RESPONSE-ADDRESS address attribute, set to (Pa,Pp).  This
//    will create a new binding on the NAT, and cause the STUN server to
//    send a Binding Response that would match the old binding, if it still
//    exists.  If the client receives the Binding Response on socket X, it
//    knows that the binding has not expired.  If the client receives the
//    Binding Response on socket Y (which is possible if the old binding
//    expired, and the NAT allocated the same public address and port to
//    the new binding), or receives no response at all, it knows that the
//    binding has expired.
//
//    The client can find the value of the binding lifetime by doing a
//    binary search through T, arriving eventually at the value where the
//    response is not received for any timer greater than T, but is
//    received for any timer less than T.
//
//    This discovery process takes quite a bit of time, and is something
//    that will typically be run in the background on a device once it
//    boots.
//
//    It is possible that the client can get inconsistent results each time
//    this process is run.  For example, if the NAT should reboot, or be
//    reset for some reason, the process may discover a lifetime than is
//    shorter than the actual one.  For this reason, implementations are
//    encouraged to run the test numerous times, and be prepared to get
//    inconsistent results.
class NatChecker {
  String serverHost;
  int serverPort;
  String localIp;
  int localPort;

  NatChecker({
    this.serverHost = "stun.hot-chilli.net",
    this.serverPort = 3478,
    this.localIp = "0.0.0.0",
    this.localPort = 54320,
  });

  List<String> _localAddresses = [];

  late StunClient _stunClient = StunClient.create(
    transport: Transport.udp,
    serverHost: serverHost,
    serverPort: serverPort,
    localIp: localIp,
    localPort: localPort,
    stunProtocol: StunProtocol.RFC3489,
  );

  Future<NatBehavior> check() async {
    _localAddresses = await _initializeLocalAddresses();
    throw UnimplementedError("此 RFC 已过时。修订后的版本是RFC 5389");
  }

  Future<List<String>> _initializeLocalAddresses() async {
    List<String> addresses = [];
    for (NetworkInterface networkInterface in await NetworkInterface.list()) {
      for (InternetAddress internetAddress in networkInterface.addresses) {
        addresses.add(internetAddress.address);
      }
    }
    return addresses;
  }
}
