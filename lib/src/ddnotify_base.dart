import 'dart:async';
import 'dart:typed_data';

import 'package:ddbus/ddbus.dart';

class Notifications {

  final bool _ownsClient;
  final DService _service;
  final Set<Capability> _capabilities = {};
  final _signalController = StreamController<NotificationSignal>.broadcast();
  StreamSubscription<NotificationSignal> _signalSubscription;

  Notifications._internal(DBusClient client, this._ownsClient):
        _service = DService(client, 'org.freedesktop.Notifications',
            '/org/freedesktop/Notifications', 'org.freedesktop.Notifications')
  {
    _signalController.onListen = _startListeningToSignals;
    _signalController.onCancel = _stopListeningToSignals;
  }

  static Future<Notifications> open([DBusClient client]) async {
    final ownsClient = client == null;
    client ??= await DBusClient.session();
    final n = Notifications._internal(client, ownsClient);
    await n._populateCapabilities();
    return n;
  }

  Future<void> close() async {
    await _signalController.close();
    if (_ownsClient) await _service.client.close();
  }

  bool hasCapability(Capability capability) => _capabilities.contains(capability);

  Set<Capability> get capabilities => _capabilities;

  Future<int> notify(Notification notification) {
    return _service.callMethod<int>('Notify', notification.toMarshalable());
  }

  Future<void> closeNotification(int id) => _service.callMethod('CloseNotification', DUint32(id));

  Future<ServerInformation> getServerInformation() async {
    final values = await _service.callMethod<List>('GetServerInformation');
    return ServerInformation._from(values);
  }

  Future<void> _populateCapabilities() async {
    _capabilities.clear();
    final names = await _service.callMethod<List<String>>('GetCapabilities');
    names
        .map((c) => _capabilityNames.indexOf(c))
        .where((index) => index != -1)
        .map((index) => Capability.values[index])
        .forEach((c) => _capabilities.add(c));
  }

  Stream<NotificationSignal> get signalStream => _signalController.stream;

  /// In case a notification is dismissed due to invoking an action, [ActionInvoked] will
  /// be returned. In other cases [NotificationClosed] will be returned.
  /// Although that guarantee relies on the fact that the dismissed signal is always sent
  /// after the action invoked -signal.
  Future<NotificationSignal> waitClosed(int notificationId) =>
      signalStream.firstWhere((s) => s.notificationId == notificationId);

  void _startListeningToSignals() {
    _signalSubscription = _service.signalStream()
        .map(_createSignal)
        .listen(_signalController.add);
  }

  Future<void> _stopListeningToSignals() async {
    await _signalSubscription?.cancel();
    _signalSubscription = null;
  }

  static NotificationSignal _createSignal(Message msg) {

    switch (msg.header.member) {
      case 'NotificationClosed':
        return NotificationClosed._from(msg.body);

      case 'ActionInvoked':
        return ActionInvoked._from(msg.body);

      default:
        return null;
    }
  }
}

class Notification {

  String appName;
  int replacesId;
  String appIcon;
  String summary;
  String body;
  Duration expireTimeout;
  final actions = <Action>[];
  final hints = Hints();

  List<DValue> toMarshalable() {
    return [
      DString(appName ?? ''),
      DUint32(replacesId ?? 0),
      DString(appIcon ?? ''),
      DString(summary),
      DString(body ?? ''),
      actions.toMarshalable(),
      hints._toMarshalable(),
      DInt32(expireTimeout?.inMilliseconds ?? -1)
    ];
  }
}

class Action {

  static const defaultKey = 'default';

  final String key;
  final String label;

  Action(this.key, this.label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Action &&
              runtimeType == other.runtimeType &&
              key == other.key &&
              label == other.label;

  @override
  int get hashCode => key.hashCode ^ label.hashCode;

  @override
  String toString() => 'Action{key: $key, label: $label}';
}

class Hints {

  final _hints = <DString, DValue>{};

  set actionIcons(bool value) => set('action-icons', value?.toDBoolean()?.toVariant());
  set category(String value) => set('category', value?.toDString()?.toVariant());
  set desktopEntry(String value) => set('desktop-entry', value?.toDString()?.toVariant());
  set imageData(ImageData value) => set('image-data', value?._toMarshalable()?.toVariant());
  set imagePath(String value) => set('image-path', value?.toDString()?.toVariant());
  set resident(bool value) => set('resident', value?.toDBoolean()?.toVariant());
  set soundFile(String value) => set('sound-file', value?.toDString()?.toVariant());
  set soundName(String value) => set('sound-name', value?.toDString()?.toVariant());
  set suppressSound(bool value) => set('suppress-sound', value?.toDBoolean()?.toVariant());
  set transient(bool value) => set('transient', value?.toDBoolean()?.toVariant());
  set x(int value) => set('x', value?.toDInt32()?.toVariant());
  set y(int value) => set('y', value?.toDInt32()?.toVariant());
  set urgency(UrgencyLevel value) => set('urgency', value?.index?.toDByte()?.toVariant());

  void set(String hint, DValue value) => _hints[DString(hint)] = value;

  DArray<DDictEntry> _toMarshalable() {
    _hints.removeWhere((key, value) => value == null);
    return DArray.dictionary(_hints, 'sv');
  }
}

extension on List<Action> {

  DArray<DString> toMarshalable() {
    final items = map((a) => [DString(a.key), DString(a.label)]).expand((e) => e).toList();
    return DArray<DString>(items);
  }
}

extension on DValue {

  DVariant toVariant() => DVariant(this);
}

class ServerInformation {

  final String name;
  final String vendor;
  final String version;
  final String specVersion;

  ServerInformation._from(List values):
        name = values[0],
        vendor = values[1],
        version = values[2],
        specVersion = values[3];

  @override
  String toString() {
    return 'ServerInformation{name: $name, vendor: $vendor, version: $version, specVersion: $specVersion}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ServerInformation &&
              runtimeType == other.runtimeType &&
              name == other.name &&
              vendor == other.vendor &&
              version == other.version &&
              specVersion == other.specVersion;

  @override
  int get hashCode => name.hashCode ^ vendor.hashCode ^ version.hashCode ^ specVersion.hashCode;
}

enum CloseReason {
  /// The notification expired.
  expired,

  /// The notification was dismissed by the user.
  dismissed,

  /// The notification was closed by a call to CloseNotification.
  closed,

  /// Undefined/reserved reasons.
  undefined
}

abstract class NotificationSignal {

  final int notificationId;

  NotificationSignal(this.notificationId);
}

class NotificationClosed extends NotificationSignal {

  final CloseReason reason;

  NotificationClosed._from(List args):
        reason = CloseReason.values[(args[1] as int) - 1],
        super(args[0]);

  @override
  String toString() {
    return 'NotificationClosed{notificationId: $notificationId, reason: $reason}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is NotificationClosed &&
              runtimeType == other.runtimeType &&
              notificationId == other.notificationId &&
              reason == other.reason;

  @override
  int get hashCode => notificationId.hashCode ^ reason.hashCode;
}

class ActionInvoked extends NotificationSignal {

  final String actionKey;

  ActionInvoked._from(List args):
        actionKey = args[1],
        super(args[0]);

  @override
  String toString() {
    return 'ActionInvoked{notificationId: $notificationId, actionKey: $actionKey}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ActionInvoked &&
              runtimeType == other.runtimeType &&
              notificationId == other.notificationId &&
              actionKey == other.actionKey;

  @override
  int get hashCode => notificationId.hashCode ^ actionKey.hashCode;
}

enum Capability {
  actionIcons,
  actions,
  body,
  bodyHyperlinks,
  bodyImages,
  bodyMarkup,
  iconMulti,
  iconStatic,
  persistence,
  sound,
}

const _capabilityNames = [
  'action-icons', 'actions', 'body', 'body-hyperlinks', 'body-images',
  'body-markup', 'icon-multi', 'icon-static', 'persistence', 'sound'
];

enum UrgencyLevel {
  low,
  normal,
  critical
}

class ImageData {
  final int width;
  final int height;
  final int rowStride;
  final bool hasAlpha;
  final int bitsPerSample;
  final int channels;
  final Uint8List data;

  ImageData(this.width, this.height, this.rowStride, this.hasAlpha, this.bitsPerSample,
      this.channels, this.data);

  DStruct _toMarshalable() {
    return DStruct(
        [
          DInt32(width),
          DInt32(height),
          DInt32(rowStride),
          DBoolean(hasAlpha),
          DInt32(bitsPerSample),
          DInt32(channels),
          DByteArray(data)
        ]
    );
  }
}
