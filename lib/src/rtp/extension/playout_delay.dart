import '../../../types/types.dart';
import 'extension.dart';

class PlayoutDelayExtension  extends HeaderExtension{
  Uint16 min_delay; //: u16,
  Uint16 max_delay; //: u16,

  PlayoutDelayExtension(this.min_delay, this.max_delay);
}
