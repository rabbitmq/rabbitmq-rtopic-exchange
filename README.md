# RabbitMQ Reverse Topic Exchange Type #

This plugin adds a __reverse topic exchange__ type to [RabbitMQ](http://www.rabbitmq.com). The exchange type is `x-rtopic`.

The idea is to be able to specify routing patterns when publishing messages. With the default topic exchange patterns are only accepted when binding queues to exchanges.

With this plugin you can decide which queues receive the message at publishing time. With the default topic exchange the decision is made during queue binding.

With this exchange your routing keys will be words separated by dots, and the binding keys will be words separated by dots as well, with the difference that on the routing keys
you can provide special characters like the `#` or the `*`. The hash `#` will match zero or more words. The star `*` will match one word.

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

## Installation and Binary Builds

This plugin is now available from the [RabbitMQ community plugins page](http://www.rabbitmq.com/community-plugins.html).
Please consult the docs on [how to install RabbitMQ plugins](http://www.rabbitmq.com/plugins.html#installing-plugins).

Then enable the plugin:

```bash
rabbitmq-plugins enable rabbitmq_rtopic_exchange
```

## Building from Source

See [Plugin Development guide](http://www.rabbitmq.com/plugin-development.html).

TL;DR: running

    make dist

will build the plugin and put build artifacts under the `./plugins` directory.


## Examples and Tests ##

There's a few tests inside the test folder. You can take a look there if you want to see some examples on how to use the plugin.

To run the tests call `make test`.

## Performance ##

Internally the plugin uses a trie like data structure, so the following has to be taken into account when binding either queues or exchanges to it.

The following applies if you have **thousands** of queues. After some benchmarks I could see that performance degraded for +1000 bindings. So if you have say, 100 bindings to this exchange, then performance should be acceptable in most cases. In any case, running your own benchmarks wont hurt. The file `rabbit_rtopic_perf.erl` has some precarious tools to run benchmarks that I ought to document at some point.

A trie performs better when doing _prefix_ searches than _suffix_ searches. For example we have the following bindings:

```
a0.b0.c0.d0
a0.b0.c1.d0
a0.b1.c0.d0
a0.b1.c1.d0
a0.b0.c2.d1
a0.b0.c2.d0
a0.b0.c2.d1
a0.b0.c3.d0
a1.b0.c0.d0
a1.b1.c0.d0
```

If we publish a message with the following routing key: `"a0.#"`, it's the same as asking "find me all the routing keys that start with `"a0"`. After the algorithm descended on level in the trie, then it needs to visit every node in the trie. So the longer the prefix, the faster the routing will behave. That is, queries of the kind "find all string with prefix", will go faster, the longer the prefix is.

On the other hand if we publish a message with the routing key `"#.d0"`, it's the same as asking "find me all the bindings with suffix `"d0"`. That would be terribly slow to do with a trie, but there's a trick. If you need to use this exchange for this kind of routing, then you can build your bindings in reverse, therefore you could do a "all prefixes" query instead of a "all suffixes" query.

If you have the needs for routing `"a0.#.c0.d0.#.f0.#"` then again, with a small amount of binding keys it should be a problem, but keep in mind that the longer the gaps represented by the `#` character, the slower the algorithm will run. AFAIK there's no easy solution for this problem.

## License ##

See LICENSE.

## Credits ##

Alvaro Videla - alvaro@rabbitmq.com
