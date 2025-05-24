import 'dart:ffi';

import '../../sip_parser/sip.dart';

/**
 * Class Location
 * 
 * @property int $contact_id
 * @property string $username
 * @property string|null $domain
 * @property string $contact
 * @property string|null $received
 * @property string|null $path
 * @property int $expires
 * @property float $q
 * @property string $callid
 * @property int $cseq
 * @property Carbon $last_modified
 * @property int $flags
 * @property string|null $cflags
 * @property string $user_agent
 * @property string|null $socket
 * @property int|null $methods
 * @property string|null $sip_instance
 * @property string|null $kv_store
 * @property string|null $attr
 *
 * @package App\Models
 */

class Location {
  // protected $table = 'location';
  // protected $primaryKey = 'contact_id';
  // public $timestamps = false;

  // protected $casts = [
  // 	'expires' => 'int',
  // 	'q' => 'float',
  // 	'cseq' => 'int',
  // 	'last_modified' => 'datetime',
  // 	'flags' => 'int',
  // 	'methods' => 'int'
  // ];
  //Function(String)
  Location(
      this.contact_id, this.username, this.domain, this.contact, this.socket);

  String contact_id;
  String username;
  String? domain;
  String contact;
  String? received;
  String? path = "";
  int expires = 0;
  double q = 0.0;
  String callid = "";
  int cseq = 0;
  DateTime last_modified = DateTime.now();
  int flags = 0;
  String? cflags;
  String user_agent = "";
  sockaddr_in socket;
  int? methods;
  String? sip_instance;
  String? kv_store;
  String? attr;
  Function(String data)? send;
}

Map<String, Location> locations = {};
