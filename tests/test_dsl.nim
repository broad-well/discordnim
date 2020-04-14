import ../discordnim

discordBot bot, readFile("secretToken"):
  commands "^":
    command "test", message:
      message.reply("hello, world!", mention=true)
      message.react("😎")

  setup:
    echo "hello, setting up"