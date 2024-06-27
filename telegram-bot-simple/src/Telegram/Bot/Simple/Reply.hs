{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE RecordWildCards #-}
module Telegram.Bot.Simple.Reply where

import           Control.Applicative     ((<|>))
import           Control.Monad
import           Control.Monad.Reader
import           Data.String
import           Data.Text               (Text)
import           GHC.Generics            (Generic)

import           Telegram.Bot.API        as Telegram hiding (editMessageText, editMessageReplyMarkup)
import           Telegram.Bot.Simple.Eff
import           Telegram.Bot.Simple.RunTG (RunTG(..))

-- | Get current 'ChatId' if possible.
currentChatId :: BotM (Maybe ChatId)
currentChatId = do
  mupdate <- asks botContextUpdate
  pure $ updateChatId =<< mupdate

getEditMessageId :: BotM (Maybe EditMessageId)
getEditMessageId = do
  mupdate <- asks botContextUpdate
  pure $ updateEditMessageId =<< mupdate

updateEditMessageId :: Update -> Maybe EditMessageId
updateEditMessageId update
    = EditInlineMessageId
      <$> (callbackQueryInlineMessageId =<< updateCallbackQuery update)
  <|> EditChatMessageId
      <$> (SomeChatId . chatId . messageChat <$> message)
      <*> (messageMessageId <$> message)
  where
    message = extractUpdateMessage update

-- | Reply message parameters.
-- This is just like 'SendMessageRequest' but without 'SomeChatId' specified.
data ReplyMessage = ReplyMessage
  { replyMessageText                  :: Text -- ^ Text of the message to be sent.
  , replyMessageMessageThreadId       :: Maybe MessageThreadId -- ^ Unique identifier for the target message thread (topic) of the forum; for forum supergroups only.
  , replyMessageParseMode             :: Maybe ParseMode -- ^ Send 'MarkdownV2', 'HTML' or 'Markdown' (legacy), if you want Telegram apps to show bold, italic, fixed-width text or inline URLs in your bot's message.
  , replyMessageEntities              :: Maybe [MessageEntity] -- ^ A JSON-serialized list of special entities that appear in message text, which can be specified instead of /parse_mode/.
  , replyMessageLinkPreviewOptions    :: Maybe LinkPreviewOptions -- ^ Link preview generation options for the message.
  , replyMessageDisableNotification   :: Maybe Bool -- ^ Sends the message silently. Users will receive a notification with no sound.
  , replyMessageProtectContent        :: Maybe Bool -- ^ Protects the contents of the sent message from forwarding and saving.
  , replyMessageReplyToMessageId      :: Maybe MessageId -- ^ If the message is a reply, ID of the original message.
  , replyMessageReplyParameters        :: Maybe ReplyParameters -- ^ Description of the message to reply to.
  , replyMessageReplyMarkup           :: Maybe SomeReplyMarkup -- ^ Additional interface options. A JSON-serialized object for an inline keyboard, custom reply keyboard, instructions to remove reply keyboard or to force a reply from the user.
  } deriving (Generic)

instance IsString ReplyMessage where
  fromString = toReplyMessage . fromString

-- | Create a 'ReplyMessage' with just some 'Text' message.
toReplyMessage :: Text -> ReplyMessage
toReplyMessage text
  = ReplyMessage text Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

replyMessageToSendMessageRequest :: SomeChatId -> ReplyMessage -> SendMessageRequest
replyMessageToSendMessageRequest someChatId ReplyMessage{..} = SendMessageRequest
  { sendMessageChatId = someChatId
  , sendMessageBusinessConnectionId = Nothing
  , sendMessageMessageEffectId = Nothing
  , sendMessageMessageThreadId = replyMessageMessageThreadId
  , sendMessageText = replyMessageText
  , sendMessageParseMode = replyMessageParseMode
  , sendMessageEntities = replyMessageEntities
  , sendMessageLinkPreviewOptions = replyMessageLinkPreviewOptions
  , sendMessageDisableNotification = replyMessageDisableNotification
  , sendMessageProtectContent = replyMessageProtectContent
  , sendMessageReplyToMessageId = replyMessageReplyToMessageId
  , sendMessageReplyMarkup = replyMessageReplyMarkup
  , sendMessageReplyParameters = replyMessageReplyParameters
  }

-- | Reply in a chat with a given 'SomeChatId'.
replyTo :: SomeChatId -> ReplyMessage -> BotM ()
replyTo someChatId rmsg = do
  let msg = replyMessageToSendMessageRequest someChatId rmsg
  void $ runTG msg

-- | Reply in the current chat (if possible).
reply :: ReplyMessage -> BotM ()
reply rmsg = do
  mchatId <- currentChatId
  case mchatId of
    Just chatId -> replyTo (SomeChatId chatId) rmsg
    Nothing     -> liftIO $ putStrLn "No chat to reply to"

-- | Reply with a text.
replyText :: Text -> BotM ()
replyText = reply . toReplyMessage

data EditMessage = EditMessage
  { editMessageText                  :: Text
  , editMessageParseMode             :: Maybe ParseMode
  , editMessageLinkPreviewOptions    :: Maybe LinkPreviewOptions
  , editMessageReplyMarkup           :: Maybe SomeReplyMarkup
  }

instance IsString EditMessage where
  fromString = toEditMessage . fromString

data EditMessageId
  = EditChatMessageId SomeChatId MessageId
  | EditInlineMessageId MessageId

toEditMessage :: Text -> EditMessage
toEditMessage msg = EditMessage msg Nothing Nothing Nothing

editMessageToEditMessageTextRequest
  :: EditMessageId -> EditMessage -> EditMessageTextRequest
editMessageToEditMessageTextRequest editMessageId EditMessage{..}
  = EditMessageTextRequest
    { editMessageTextText = editMessageText
    , editMessageTextParseMode = editMessageParseMode
    , editMessageTextLinkPreviewOptions = editMessageLinkPreviewOptions
    , editMessageTextReplyMarkup = editMessageReplyMarkup
    , editMessageEntities = Nothing
    , ..
    }
  where
    ( editMessageTextChatId,
      editMessageTextMessageId,
      editMessageTextInlineMessageId )
      = case editMessageId of
          EditChatMessageId chatId messageId
            -> (Just chatId, Just messageId, Nothing)
          EditInlineMessageId messageId
            -> (Nothing, Nothing, Just messageId)

editMessageToReplyMessage :: EditMessage -> ReplyMessage
editMessageToReplyMessage EditMessage{..} = (toReplyMessage editMessageText)
  { replyMessageParseMode = editMessageParseMode
  , replyMessageLinkPreviewOptions = editMessageLinkPreviewOptions
  , replyMessageReplyMarkup = editMessageReplyMarkup
  }

editMessage :: EditMessageId -> EditMessage -> BotM ()
editMessage editMessageId emsg = do
  let msg = editMessageToEditMessageTextRequest editMessageId emsg
  void $ runTG msg

editUpdateMessage :: EditMessage -> BotM ()
editUpdateMessage emsg = do
  mEditMessageId <- getEditMessageId
  case mEditMessageId of
    Just editMessageId -> editMessage editMessageId emsg
    Nothing            -> liftIO $ putStrLn "Can't find message to edit!"

editUpdateMessageText :: Text -> BotM ()
editUpdateMessageText = editUpdateMessage . toEditMessage

replyOrEdit :: EditMessage -> BotM ()
replyOrEdit emsg = do
  uid <- asks (fmap userId . (messageFrom =<<) . (extractUpdateMessage =<<) . botContextUpdate)
  botUserId <- asks (userId . botContextUser)
  if uid == Just botUserId
     then editUpdateMessage emsg
     else reply (editMessageToReplyMessage emsg)
