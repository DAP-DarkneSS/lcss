--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RankNTypes #-}
import           Data.Monoid
import           Hakyll

import Data.List.Extra
import Data.Char
import Control.Monad

import ImageRefsCompiler


--------------------------------------------------------------------------------
main :: IO ()
main = hakyll $ do
    match "images/*" $ do
        route   idRoute
        compile copyFileCompiler

    match "css/*" $ do
        route   idRoute
        compile compressCssCompiler

    match "text/*.md" $ do
        route $ customRoute $ dropPrefix "text/" . unmdize . toFilePath
        compile $ pandocCompiler
                >>= loadAndApplyTemplate "templates/default.html" defaultContext
                >>= relativizeUrls
                >>= imageRefsCompiler

    listed (defListedConfig "plugins") {
                                        customTemplate = Just "plugin",
                                        customItemsContext = do
                                            fp <- loadCurrentPath
                                            pure $ listField "plugins" (isCurrentPageField fp <> defaultContext) (loadAll $ "text/plugins/*.md" .&&. hasVersion "preprocess")
                                       }

    listed (defListedConfig "news") { customContext = dates, customTemplate = Just "news-item", subOrder = recentFirst, verPreprocess = False }

    listed (defListedConfig "concepts") { verPreprocess = False }

    listed (defListedConfig "development") {
                                            customTemplate = Just "development-item",
                                            customItemsContext = do
                                                fp <- loadCurrentPath
                                                pure $ listField "develSections" (isCurrentPageField fp <> defaultContext) (loadAll $ "text/development/*.md" .&&. hasVersion "preprocess")
                                           }

    match "templates/*" $ compile templateBodyCompiler

unmdize :: String -> String
unmdize s = take (length s - 3) s

dropPrefix :: String -> String -> String
dropPrefix s = drop $ length s

--------------------------------------------------------------------------------

data ListedConfig = ListedConfig {
                        section :: String,
                        customTemplate :: Maybe String,
                        customContext :: Context String,
                        customItemsContext :: Compiler (Context String),
                        listTitle :: String,
                        listFieldName :: String,
                        listTemplate :: String,
                        createRoot :: Bool,
                        verPreprocess :: Bool,
                        subOrder :: forall m a. MonadMetadata m => [Item a] -> m [Item a]
                    }

defListedConfig :: String -> ListedConfig
defListedConfig section = ListedConfig {
                              section = section,
                              customTemplate = Nothing,
                              customContext = mempty,
                              customItemsContext = pure mempty,
                              listTitle = section',
                              listFieldName = section,
                              listTemplate = section,
                              createRoot = True,
                              verPreprocess = True,
                              subOrder = pure
                          }
    where section' = toUpper (head section) : tail section

listed :: ListedConfig -> Rules ()
listed ListedConfig { .. } = do
    when verPreprocess $
        match filesPat $ version "preprocess" $ do
            route $ customRoute defaultTextRoute
            compile getResourceBody

    match filesPat $ do
        route $ customRoute defaultTextRoute
        compile $ do
            ctx' <- customItemsContext
            pandocCompiler
                  >>= loadAndApplyCustom (ctx' <> ctx)
                  >>= loadAndApplyTemplate "templates/default.html" (ctx' <> ctx)
                  >>= relativizeUrls
                  >>= imageRefsCompiler

    when createRoot $
        create [fromFilePath section] $ do
            route idRoute
            compile $ do
                items <- loadAll (filesPat .&&. hasNoVersion) >>= subOrder
                let listCtx = constField "title" listTitle <> listField listFieldName ctx (pure items) <> ctx
                makeItem ""
                    >>= loadAndApplyTemplate (tplPath listTemplate) listCtx
                    >>= loadAndApplyTemplate "templates/default.html" listCtx
                    >>= relativizeUrls

    where filesPat = fromGlob $ "text/" <> section <> "/*.md"
          ctx = customContext <> defaultContext
          tplPath path = fromFilePath $ "templates/" <> path <> ".html"
          loadAndApplyCustom | Just tpl <- customTemplate = loadAndApplyTemplate (tplPath tpl)
                             | otherwise = const pure

date :: Context String
date = dateField "date" "%B %e, %Y"

dateAndTime :: Context String
dateAndTime = dateField "dateandtime" "%B %e, %Y, %H:%M"

dates :: Context String
dates = date <> dateAndTime

isCurrentPage :: FilePath -> Item a -> Compiler String
isCurrentPage fp item = do
    rt <- getRoute $ itemIdentifier item
    pure $ if rt == Just fp
            then "true"
            else "false"

isCurrentPageField :: FilePath -> Context a
isCurrentPageField = field "isCurrentPage" . isCurrentPage

defaultTextRoute :: Identifier -> FilePath
defaultTextRoute = snd . breakEnd (== '/') . unmdize . toFilePath

loadCurrentPath :: Compiler FilePath
loadCurrentPath = defaultTextRoute . fromFilePath . drop 2 <$> getResourceFilePath
