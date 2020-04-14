import ../discordnim

discordBot bot, readFile("secretToken"):
  commands "^":
    command "test", message:
      """ A very cool command indeed. """
      message.reply("hello, world!", mention=true)
      message.react("😎")

  setup:
    echo "hello, setting up"