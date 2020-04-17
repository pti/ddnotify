import 'package:ddbus/ddbus.dart';
import 'package:ddnotify/ddnotify.dart';

void main() async {

  DBusClient.logger = (LogLevel level, LogType type, String text, Message message, dynamic error, StackTrace stack) {
    print ('${type?.name}: ${text ?? ''} ${message?.header} ${message?.body} $error $stack');
  };

  final n = await Notifications.open();
  print('Server capabilities: ${n.capabilities}');
  print('Server information: ${await n.getServerInformation()}');

  const actionId1 = 'action1';

  final notification = Notification()
    ..summary = 'Hello world!'
    ..body = 'Notification body text'
    ..hints.urgency = UrgencyLevel.low
    ..actions.add(Action(actionId1, 'Done'))
    ..actions.add(Action(Action.defaultKey, 'This label might be ignored - the action is invoked e.g. when user clicks the notification'))
    ;

  final id = await n.notify(notification);
  final signal = await n.waitClosed(id);
  print(signal);

  if (signal is ActionInvoked) {

    switch (signal.actionKey) {
      case actionId1:
        print('execute action 1');
        break;

      case Action.defaultKey:
        print('execute default action');
        break;

      default:
        print('unknown action: ${signal.actionKey}');
        break;
    }
  }

  await n.close();
}
