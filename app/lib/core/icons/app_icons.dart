import 'app_icon.dart';
import 'icon_data.dart';

export 'app_icon.dart';
export 'icon_data.dart';

/// Friendly names for board icons. Add a name here the first time a screen needs an icon
/// (find its hash in the board markup), and keep using it everywhere after.
abstract final class AppIcons {
  // Navigation
  static const home = Ic.i36de4e;
  static const dashboard = Ic.i51bfd1;
  static const clients = Ic.ic48f53;
  static const clientsAlt = Ic.ia1dbf9;
  static const approvals = Ic.i90d108;
  static const approvalsAlt = Ic.ife32c3;
  static const trainers = Ic.idc5e89;
  static const person = Ic.i404bd9;
  static const calendar = Ic.i4d269a;
  static const calendarAlt = Ic.i8d5311;
  static const activity = Ic.i5598b7;
  static const programs = Ic.i41f8f8;
  static const dumbbell = Ic.idb82f1;
  static const exercises = Ic.i721d88;
  static const exercisesAlt = Ic.ib75651;
  static const nutrition = Ic.i656357;
  static const apple = Ic.ia113d2;
  static const food = Ic.i84f276;
  static const habitsSupps = Ic.i324a8b;
  static const checkCircle = Ic.i0fa27d;
  static const forms = Ic.ia7ae6e;
  static const clipboard = Ic.i78d420;
  static const content = Ic.i8bcf33;
  static const library = Ic.ia675ba;
  static const automations = Ic.iaf642f;
  static const bolt = Ic.i3a80f3;
  static const emails = Ic.id9c341;
  static const mail = Ic.i5d26cf;
  static const settings = Ic.ifc70fa;
  static const settingsAlt = Ic.i734097;
  static const target = Ic.i2f6c9f;
  static const progress = Ic.i10c27c;
  static const menu = Ic.i0b891c;
  static const checkinsBadge = Ic.ifb0c1c;

  // Actions
  static const check = Ic.i144814;
  static const close = Ic.ia67683;
  static const plus = Ic.iad82be;
  static const minus = Ic.i2adc2e;
  static const chevronDown = Ic.if21f98;
  static const chevronUp = Ic.i00d583;
  static const chevronRight = Ic.ie95422;
  static const chevronLeft = Ic.i67eb83;
  static const collapse = Ic.ie42143;
  static const sidebar = Ic.ibd7990;
  static const trash = Ic.ib5ae1a;
  static const trashAlt = Ic.id31bab;
  static const edit = Ic.i956f97;
  static const dots = Ic.ifc48d4;
  static const info = Ic.i1d91d0;
  static const infoAlt = Ic.ieefc47;
  static const clock = Ic.i64a3c5;
  static const star = Ic.i996bdf;
  static const eye = Ic.i967eb2;
  static const assign = Ic.if2e92a;
  static const play = Ic.i6c21db;
  static const alert = Ic.ib71b81;
  static const bell = Ic.i65155b;
  static const bellRing = Ic.iad0c97;
  static const send = Ic.i29b5ba;
  static const search = Ic.if41b1a;
  static const searchAlt = Ic.i68f93f;
  static const swap = Ic.i0df96b;
  static const swapAlt = Ic.i2d73c8;
  static const stop = Ic.ia75f78;
  static const moon = Ic.i535012;
  static const external = Ic.i10e84b;
  static const camera = Ic.ia91a2e;
  static const reset = Ic.idbaee5;
  static const doc = Ic.i559dc5;
  static const bowl = Ic.id0a3ac;
  static const sun = Ic.ieb8c47;
  static const copy = Ic.if1fec0;
  static const drag = Ic.i6309eb;
  static const water = Ic.i317840;
  static const photo = Ic.i12f578;
  static const export = Ic.i5eeb6e;
  static const filter = Ic.ib740a9;
  static const download = Ic.ie16151;

  // Login and setup (ClientLogin board)
  static const flame = Ic.i51337a;
  static const heartPulse = Ic.i4345de;
  static const lock = Ic.i0fe635;
  static const logout = Ic.ic0d03f;
  static const phone = Ic.ie0d0d2;
  static const arrowRight = Ic.i2f724c;

  // Account links (ClientJoinLink, ClientHealth boards)
  static const whatsapp = Ic.i872094;
  static const link = Ic.i7b24ef;
  static const user = Ic.ib023cf;
  static const heart = Ic.i7782ae;

  // Client Home (ClientHome board)
  static const run = Ic.i4345de;
  static const steps = Ic.i28b540;
  static const pill = Ic.i5007dd;
  static const flag = Ic.if60d32;
  static const pin = Ic.i292230;
  static const pause = Ic.i07c5c5;
  static const restart = Ic.id3785d;
  static const video = Ic.i379873;
  // Client More (board ClientMore)
  static const gear = Ic.i21fee3;
  static const ruler = Ic.i55367c;
  static const shield = Ic.idc2ade;
  static const pulse = Ic.i02c7a2;
  static const help = Ic.i02c933;
  static const scale = Ic.i9c63ed;
  static const downloadAlt = Ic.i535d22;
  static const file = Ic.ibada39;
  // Client Library (board ClientLibrary)
  static const bookmark = Ic.i5d68f8;
  static const downloadLine = Ic.i78fb3d;
  // Not on any board (full-screen video); same 24 grid and stroke as the board icons.
  static const expand = AppIconData('0 0 24 24', '<path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5"/>');
}
