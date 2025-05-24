import '../../../types/types.dart';
import 'extension.dart';

class TransportCcExtension  extends HeaderExtension{
  Uint16 transport_sequence;
  TransportCcExtension(this.transport_sequence);
}
