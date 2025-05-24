/**
 * Class Subscriber
 * 
 * @property int $id
 * @property string $username
 * @property string $domain
 * @property string $password
 * @property string $email_address
 * @property string $ha1
 * @property string $ha1_sha256
 * @property string $ha1_sha512t256
 * @property string|null $rpid
 *
 * @package App\Models
 */
class Subscriber
{
	//protected $table = 'subscriber';
	//public $timestamps = false;

	// protected $hidden = [
	// 	'password'
	// ];

	//protected $fillable = [
		String username;
	String domain;
		String password;
		String? email_address;
		String ha1;
		String ha1_sha256;
		String ha1_sha512t256;
		String? rpid;

    Subscriber(this.username,this.domain,this.password,this.ha1,this.ha1_sha256,this.ha1_sha512t256);
	//];
}
