import ../discordnim

discordBot bot, readFile("secretToken"):
  commands "^":
    command "test", message, args:
      message.reply("hello, world!", mention=true)
      message.react("😎")

  setup:
    echo "hello, setting up"