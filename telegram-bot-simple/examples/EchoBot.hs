{-# LANGUAGE OverloadedStrings #-}
module Main where

import           Data.Text                        (Text)
import qualified Data.Text                        as Text
import           Data.Maybe

import           Telegram.Bot.API
import           Telegram.Bot.Simple
import           Telegram.Bot.Simple.UpdateParser (updateMessageText, updateMessageSticker)
import           Telegram.Bot.API.InlineMode.InlineQueryResult
import           Telegram.Bot.API.InlineMode.InputMessageContent (defaultInputTextMessageContent)

type Model = ()

data Action
  = InlineEcho InlineQueryId Text
  | StickerEcho InputFile ChatId
  | Echo Text

echoBot :: BotApp Model Action
echoBot = BotApp
  { botInitialModel = ()
  , botAction = updateToAction
  , botHandler = handleAction
  , botJobs = []
  }

updateToAction :: Update -> Model -> Maybe Action
updateToAction update _
  | isJust $ updateInlineQuery update =  do
      query <- updateInlineQuery update
      let queryId = inlineQueryId query
      let msg =  inlineQueryQuery query
      Just $ InlineEcho queryId msg
  | isJust $ updateMessageSticker update = do
    fileId <- stickerFileId <$> updateMessageSticker update
    chatOfUser <- updateChatId update
    pure $ StickerEcho (InputFileId fileId) chatOfUser
  | otherwise = case updateMessageText update of
      Just text -> Just (Echo text)
      Nothing   -> Nothing

handleAction :: Action -> Model -> Eff Action Model
handleAction action model = case action of
  InlineEcho queryId msg -> model <# do
    let result = (defInlineQueryResultGeneric (InlineQueryResultId msg))
          { inlineQueryResultTitle = Just msg
          , inlineQueryResultInputMessageContent = Just (defaultInputTextMessageContent msg)
          }
        thumbnail = defInlineQueryResultGenericThumbnail result
        article = defInlineQueryResultArticle thumbnail
        answerInlineQueryRequest = defAnswerInlineQuery queryId [article]
    _ <- runTG  answerInlineQueryRequest
    return ()
  StickerEcho file chat -> model <# do
    _ <- runTG
        (defSendSticker (SomeChatId chat) file)
    return ()
  Echo msg -> model <# do
    pure msg -- or replyText msg

run :: Token -> IO ()
run token = do
  env <- defaultTelegramClientEnv token
  startBot_ echoBot env

main :: IO ()
main = do
  putStrLn "Please, enter Telegram bot's API token:"
  token <- Token . Text.pack <$> getLine
  run token
