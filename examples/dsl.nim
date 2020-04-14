## Has to be compiled with 
## '-d:ssl' flag

import discordnim

discordBot bot, "Bot <Token>":
    command "ping", msg:
        msg.reply "pong"