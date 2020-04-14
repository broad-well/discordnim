import discord, objects, restapi
import strutils, asyncfutures, strformat, asyncdispatch, options, json, uri, tables
import macros

type
    CommandInvocation* = object
        message*: Message
        args*: seq[string]
        shard*: Shard
    CommandHandler = object
        fullPrefix: string
        handlerBody: NimNode
        handlerInvocationLit: NimNode
        help: Option[string]

proc reply*(self: CommandInvocation, response: string, mention: bool = false, wait: bool = false) =
    ## Reply to the given `CommandInvocation` with the given response. Optionally mention the author of the invoking message.
    ## Optionally wait for the message to be sent.
    let prefix = if mention: &"<@{self.message.author.id}> " else: ""
    let future = self.shard.channelMessageSend(self.message.channel_id, prefix & response)
    if wait:
        discard waitFor future
    else:
        asyncCheck future

proc react*(self: CommandInvocation, emoji: string) =
    ## React to the message that invoked the command.
    ## `emoji` can be an actual emoji symbol, an emoji code with colons, or an emoji ID
    asyncCheck self.shard.channelMessageReactionAdd(self.message.channel_id, self.message.id, encodeUrl(emoji))

# --------------------
# Static region begins
# --------------------

## Parse command declaration (command "ping", msg: <body>) to an ``of`` branch of the message handler
proc parseCommandToHandler(commandNode: NimNode, prefix: string = ""): CommandHandler =
    expectLen(commandNode, 4)
    expectIdent(commandNode[0], "command")
    result.fullPrefix = prefix & commandNode[1].strVal
    result.handlerInvocationLit = commandNode[2]
    result.handlerBody = commandNode[3]
    if result.handlerBody[0].kind == nnkTripleStrLit:
        let rawHelpText = result.handlerBody[0].strVal
        result.handlerBody.del(0)
        result.help = some(rawHelpText)

proc toOfBranch(handler: CommandHandler, messageId: NimNode): NimNode =
    let handlerMessageLit = handler.handlerInvocationLit
    let handlerBody = handler.handlerBody

    let body = quote do:
        let `handlerMessageLit` = `messageId`
        `handlerBody`
    
    return nnkOfBranch.newTree(newLit(handler.fullPrefix), body)

macro discordBot*(botVarName: untyped, token: string, body: untyped): untyped =
    ## Parent macro for the command-based Discord bot DSL.
    ## Find examples in the README and the `examples/` folder.

    # case tokens[0]:
    let tokensLit = genSym(ident = "tokens")
    let messageLit = genSym(ident = "message")
    let tokenDispatchCaseStmt = nnkCaseStmt.newTree(nnkBracketExpr.newTree(tokensLit, newLit(0)))
    var subcommands: Table[string, seq[CommandHandler]]
    var setup = newStmtList()
    
    for commandSet in body:
        expectKind(commandSet, {nnkCommand, nnkCall})
        expectKind(commandSet[0], nnkIdent)
        case commandSet[0].strVal
        of "command":
            tokenDispatchCaseStmt.add(parseCommandToHandler(commandSet).toOfBranch(messageLit))

        of "commands":
            expectKind(commandSet[1], nnkStrLit)
            let prefix = commandSet[1].strVal
            expectKind(commandSet[2], nnkStmtList)

            subcommands[prefix] = newSeqOfCap[CommandHandler](commandSet[2].len)
            for command in commandSet[2]:
                let handler = parseCommandToHandler(command, prefix)
                tokenDispatchCaseStmt.add(handler.toOfBranch(messageLit))
                subcommands[prefix].add(handler)
            
        of "setup":
            expectKind(commandSet[1], nnkStmtList)
            setup = commandSet[1]
        else:
            error(&"unknown discordBot top-level directive: {commandSet[0].strVal}", commandSet)
    
    result = quote do:
        import asyncdispatch, strutils

        proc discordnim_onMessageCreate(s: Shard; mc: MessageCreate) =
            if s.cache.me.id == mc.author.id: return
            let `tokensLit` = mc.content.split(" ")
            if `tokensLit`.len == 0: return
            let `messageLit` = CommandInvocation(message: mc, args: `tokensLit`, shard: s)
            `tokenDispatchCaseStmt`

        let `botVarName` = newShard(`token`)

        proc endSession() {. noconv .} =
            echo "Stopping..."
            waitFor `botVarName`.disconnect()

        setControlCHook(endSession)

        let removeProc = `botVarName`.addHandler(EventType.message_create, discordnim_onMessageCreate)
        `setup`
        waitFor `botVarName`.startSession()
        removeProc()

    debugEcho result.toStrLit