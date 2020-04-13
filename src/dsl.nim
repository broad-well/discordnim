import discord, objects, restapi
import strutils, asyncfutures, strformat, asyncdispatch, options
import macros

type
    CommandInvocation = object
        message*: Message
        shard*: Shard

proc reply*(self: CommandInvocation, response: string, mention: bool = false, wait: bool = false) =
    let prefix = if mention: &"<@{self.message.author.id}> " else: ""
    let future = self.shard.channelMessageSend(self.message.channel_id, prefix & response)
    if wait:
        discard waitFor future
    else:
        asyncCheck future

# Internal literals
const intLitPrefix = "discordnim_"

proc expectLitCompatibleWithIntLit(lit: NimNode) =
    if lit.strVal.startsWith(intLitPrefix):
        error(&"literal {lit} may not start with reserved internal prefix {intLitPrefix}", lit)

## Parse command declaration (command "ping", message, args: <body>) to an ``of`` branch of the message handler
proc parseCommandDeclarationToOfBranch(messageIdent: NimNode, tokensIdent: NimNode, commandNode: NimNode, prefix: string = ""): NimNode =
    expectLen(commandNode, 5)
    expectIdent(commandNode[0], "command")
    let messageVarName = commandNode[2]
    let argsVarName = commandNode[3]
    let callbackBody = commandNode[4]
    expectLitCompatibleWithIntLit(messageVarName)
    expectLitCompatibleWithIntLit(argsVarName)

    let command = prefix & commandNode[1].strVal
    let body = quote do:
        let `messageVarName` = `messageIdent`
        let `argsVarName` = `tokensIdent`[1..^1]
        `callbackBody`
    
    return nnkOfBranch.newTree(newLit(command), body)


macro discordBot*(botVarName: untyped, token: string, body: untyped): untyped =
    # case tokens[0]:
    let tokensLit = newIdentNode(intLitPrefix & "tokens")
    let messageLit = newIdentNode(intLitPrefix & "message")
    let tokenDispatchCaseStmt = nnkCaseStmt.newTree(nnkBracketExpr.newTree(tokensLit, newLit(0)))
    var setup = newStmtList()
    
    for commandSet in body:
        expectKind(commandSet, {nnkCommand, nnkCall})
        expectKind(commandSet[0], nnkIdent)
        case commandSet[0].strVal
        of "command":
            tokenDispatchCaseStmt.add(parseCommandDeclarationToOfBranch(messageLit, tokensLit, commandSet))
        of "commands":
            expectKind(commandSet[1], nnkStrLit)
            let prefix = commandSet[1].strVal
            expectKind(commandSet[2], nnkStmtList)
            for command in commandSet[2]:
                tokenDispatchCaseStmt.add(parseCommandDeclarationToOfBranch(messageLit, tokensLit, command, prefix=prefix))
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
            let `messageLit` = CommandInvocation(message: mc, shard: s)
            `tokenDispatchCaseStmt`

        let `botVarName` = newShard(`token`)

        proc endSession() {. noconv .} =
            waitFor `botVarName`.disconnect()

        setControlCHook(endSession)

        let removeProc = `botVarName`.addHandler(EventType.message_create, discordnim_onMessageCreate)
        `setup`
        waitFor `botVarName`.startSession()
        removeProc()

    # debugging
    debugEcho result.toStrLit
