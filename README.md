# BoomNotifier

[![hex](https://img.shields.io/hexpm/v/boom_notifier?color=78529a)](https://hex.pm/packages/boom_notifier)
[![Elixir CI](https://github.com/wyeworks/boom/actions/workflows/elixir.yml/badge.svg)](https://github.com/wyeworks/boom/actions/workflows/elixir.yml)

---

This package allows your Phoenix application to send notifications whenever
an exception is raised. By default it includes an email and a webhook notifier, 
you can also implement custom ones, or use some of the independently realeased notifiers listed below.

It was inspired by the [ExceptionNotification](https://github.com/smartinez87/exception_notification)
gem that provides a similar functionality for Rack/Rails applications.

You can read the full documentation at [https://hexdocs.pm/boom_notifier](https://hexdocs.pm/boom_notifier).

## Installation

The package can be installed by adding `boom_notifier` to your list of dependencies in
`mix.exs`:

```elixir
def deps do
  [
    {:boom_notifier, "~> 0.8.0"}
  ]
end
```

## Getting started

This is an example for setting up an email notifier, you can see the full [list of available notifiers here](#notifiers).

#### Email notifier

BoomNotifier has built in support for both [Bamboo](https://github.com/thoughtbot/bamboo) and [Swoosh](https://github.com/swoosh/swoosh).

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
      notifier: BoomNotifier.MailNotifier.Bamboo,
      # or to use Swoosh
      # notifier: BoomNotifier.MailNotifier.Swoosh,
      options: [
        mailer: YourApp.Mailer,
        from: "me@example.com",
        to: "foo@example.com",
        subject: "BOOM error caught"
      ]

  # ...
```

For the email to be sent, you need to define a valid mailer in the `options` keyword list. You can customize the `from`, `to` and `subject` attributes.

`subject` will be truncated at 80 chars, if you want more add the option `max_subject_length`.

## Notifiers

BoomNotifier uses notifiers to deliver notifications when errors occur in your applications. By default, 2 notifiers are available:

* [Email notifier](docs/notifiers/email.md)
* [Webhook notifier](docs/notifiers/webhook.md)

You can also choose from these independetly-released notifiers:

* [Slack notifier](https://github.com/wyeworks/boom_slack_notifier)

On top of this, you can easily implement your own [custom notifier](docs/notifiers/custom.md).

#### Multiple notifiers

BoomNotifier allows you to setup multiple notifiers, like in the example below:

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    notifiers: [
      [
        notifier: BoomNotifier.WebhookNotifier,
        options: [
          url: "http://example.com",
        ]
      ],
      [
        notifier: CustomNotifier,
        options: # ...
      ]
    ]

    #...
end
```

## Throttling notifications

By default, `BoomNotifier` will send a notification every time an exception is
raised.

There are two throttling mechanisms you can use to reduce notification rate. Counting
based and time based throttling. The former allows notifications to be delivered
on exponential error counting and the latter based on time throttling, that is
if a predefined amount of time has passed from the last error.

### Count Based Throttle

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    notifiers: [
        # ...
      ],
    groupping: :count,
    count: :exponential,
    time_limit: :timer.minutes(30)
end
```

#### Exponential

It uses a formula of `log2(errors_count)` to determine whether to send a
notification, based on the accumulated error count for each specific
exception. This makes the notifier only send a notification when the count
is: 1, 2, 4, 8, 16, 32, 64, 128, ..., (2\*\*n).

You can also set an optional max value.

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    count: :exponential,
    notifiers: [
      # ...
    ]
```

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    count: [exponential: [limit: 100]]
    notifiers: [
      # ...
    ]
```

### Time Based Throttle

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    notifiers: [
        # ...
      ],
    groupping: :time,
    throttle: :timer.minutes(1)
end
```

### Time Limit

Both groupping strategies allow you to define a time limit that tells boom to deliver a notification if the amount
of time has passed from the last time a notification was sent or error groupping started.

If specified, a notification will be triggered even though the groupping strategy does not met the criteria. For
time based throttling this is usefull if errors keep appearing before the throttle time and for count based throttle
to reset (and notify) the grupping after a certain time period.

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    count: [:exponential],
>>>>>>> d272dfa (update README.md)
    time_limit: :timer.minutes(30),
    notifier: CustomNotifier

  # ...
end
```

## Custom data or Metadata

By default, `BoomNotifier` will **not** include any custom data from your
requests.

However, there are different strategies to decide which information do
you want to include in the notifications using the `:custom_data` option
with one of the following values: `:assigns`, `:logger` or both.

The included information will show up in your notification, in a new section
titled "Metadata".

### Assigns

This option will include the data that is in the [connection](https://hexdocs.pm/plug/Plug.Conn.html)
`assigns` field.

You can also specify the fields you want to retrieve from `conn.assigns`.

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    custom_data: :assigns,
    notifiers: [
      # ...
    ]
```

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    custom_data: [assigns: [fields: [:current_user, :session_data]]],
    notifiers: [
      # ...
    ]
```

Example of adding custom data to the connection:

```elixir
assign(conn, :name, "John")
```

### Logger

This option will include the data that is in the [Logger](https://hexdocs.pm/logger/Logger.html)
`metadata` field.

You can also specify the fields you want to retrieve from `Logger.metadata()`.

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    custom_data: :logger,
    notifiers: [
      # ...
    ]
```

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    custom_data: [logger: [fields: [:request_id, :current_user]]],
    notifiers: [
      # ...
    ]
```

Example of adding custom data to the logger:

```elixir
Logger.metadata(name: "John")
```

### Using both

You can do any combination of the above settings to include data
from both sources. The names of the fields are independent for each
source, they will appear under the source namespace.

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    custom_data: [
      [assigns: [fields: [:current_user]]],
      [logger: [fields: [:request_id, :current_user]]]
    ],
    notifiers: [
      # ...
    ]
   # ...
end
```

## Ignore exceptions

By default, all exceptions are captured by Boom. The `:ignore_exceptions` setting is provided to ignore exceptions of a certain kind. Said exceptions will not generate any kind of notification from Boom.

```elixir
defmodule YourApp.Router do
  use Phoenix.Router

  use BoomNotifier,
    ignore_exceptions: [
      HTTPoison.Error, MyApp.CustomException
    ],
    notifiers: [
      # ...
    ]
   # ...
end
```

## Implementation details

Boom uses `Plug.ErrorHandler` to trigger notifications.
If you are already using that module you must use `BoomNotifier` after it.

## Compatibility

This library aims to be compatible with Elixir versions from 1.10 to 1.17
although it might work with other versions.

## License

BoomNotifier is released under the terms of the [MIT License](https://github.com/wyeworks/boom/blob/master/LICENSE).

## Credits

The authors of this project are [Ignacio](https://github.com/iaguirre88) and [Jorge](https://github.com/jmbejar). It is sponsored and maintained by [Wyeworks](https://www.wyeworks.com).
