import '../../sip_parser/sip.dart';

/**
 * Class DrGateway
 * 
 * @property int $id
 * @property string $gwid
 * @property int $type
 * @property string $address
 * @property int $strip
 * @property string|null $pri_prefix
 * @property string|null $attrs
 * @property int $probe_mode
 * @property int $state
 * @property string|null $socket
 * @property string|null $description
 *
 * @package App\Models
 */
class Gateway {
  //protected $table = 'dr_gateways';
  //public $timestamps = false;

  //protected $casts = [
  // 'type' => 'int',
  // 'strip' => 'int',
  // 'probe_mode' => 'int',
  // 'state' => 'int'
  //];
  Gateway(this.gwid, this.type, this.address, this.strip, this.probe_mode,
      this.state, this.socket, this.send);

  //protected $fillable = [
  String gwid;
  int type;
  String address;
  int strip;
  String? pri_prefix;
  String? attrs;
  int probe_mode;
  int state;
  sockaddr_in socket;
  String? description;
  Function send;
  //];
}
