# RabbitMQ Reverse Topic Exchange Type #

This plugin adds a __reverse topic exchange type__ to [RabbitMQ](http://www.rabbitmq.com).

The idea is to be able to specify routing patterns when publishing messages. With the default topic exchange patterns are only accepted when binding queues to exchanges.

With this plugin you can decide which queues receive the message at publishing time. With the default topic exchange the decision is made during queue binding.

With this exchange your routing keys will be words separated by dots, and the routing keys will be words separated by dots as well, with the difference that you can
provide special characters like the `#` or the `*`. The hash will match zero or more words. The start will match one words.

## Usage ##

If we have the following setup, (we assume the exchange is of type _rtopic_):

- Queue _A_ bound to exchange _rtopic_ with routing key `"server1.app1.mod1.info"`.
- Queue _B_ bound to exchange _rtopic_ with routing key `"server1.app1.mod1.error"`.
- Queue _C_ bound to exchange _rtopic_ with routing key `"server1.app2.mod1.info"`.
- Queue _D_ bound to exchange _rtopic_ with routing key `"server2.app2.mod1.warning"`.
- Queue _E_ bound to exchange _rtopic_ with routing key `"server1.app1.mod2.info"`.
- Queue _F_ bound to exchange _rtopic_ with routing key `"server2.app1.mod1.info"`.

Then we execute the following message publish actions.

```erlang
%% Parameter order is: message, exchange name and routing key.

basic_publish(Msg, "rtopic", "server1.app1.mod1.info").
%% message is only received by queue A.

basic_publish(Msg, "rtopic", "*.app1.mod1.info").
%% message is received by queue A and F.

basic_publish(Msg, "rtopic", "#.info").
%% message is received by queue A, C, E and F.

basic_publish(Msg, "rtopic", "#.mod1.info").
%% message is received by queue A, C, and F.

basic_publish(Msg, "rtopic", "#").
%% message is received by every queue bound to the exchange.

basic_publish(Msg, "rtopic", "server1.app1.mod1.*").
%% message is received by queues A and B.

basic_publish(Msg, "rtopic", "server1.app1.#").
%% message is received by queues A, B and E.
```

The exchange type used when declaring an exchange is `x-rtopic`.

## Installing the plugin ##

To build the exchange follow the instructions here [Plugin Development Guide](http://www.rabbitmq.com/plugin-development.html) to prepare the RabbitMQ Umbrella.

Then clone this repository inside your umbrella folder and run make:

```bash
cd umbrella-folder
git clone https://github.com/videlalvaro/rabbitmq-rtopic-exchange.git
cd rabbitmq-rtopic-exchange
make
```

Then inside the `dist` folder you will have the following files:

```bash
amqp_client-0.0.0.ez
rabbit_common-0.0.0.ez
rabbitmq_rtopic_exchange-0.0.0.ez
```

Copy them all into your broker plugins folder except for `rabbit_common-*.ez`. Then enable the plugin by using the `rabbitmq-plugins` script.

## Examples and Tests ##

There's a few tests inside the test folder. You can take a look there if you want to see some examples on how to use the plugin.

To run the tests call `make test`.

## License ##

See LICENSE.

## Credits ##

Alvaro Videla - alvaro@rabbitmq.com