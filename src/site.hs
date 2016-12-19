--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid
import           Hakyll

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

    match ("text/plugins/*.md" .||. "text/plugins/*/*.md") $ version "preprocess" $ do
        route $ customRoute $ dropPrefix "text/plugins/" . unmdize . toFilePath
        compile $ getResourceBody

    match ("text/plugins/*.md" .||. "text/plugins/*/*.md") $ do
        route $ customRoute $ dropPrefix "text/plugins/" . unmdize . toFilePath
        compile $ do
                let ctx = pluginsCtx True
                pandocCompiler
                    >>= loadAndApplyTemplate "templates/plugin.html" ctx
                    >>= loadAndApplyTemplate "templates/default.html" ctx
                    >>= relativizeUrls
                    >>= imageRefsCompiler

    create ["plugins"] $ do
        route idRoute
        compile $ do
            let pluginsCtx' = constField "title" "Plugins" <> pluginsCtx False
            makeItem ""
                >>= loadAndApplyTemplate "templates/plugins.html" pluginsCtx'
                >>= loadAndApplyTemplate "templates/default.html" pluginsCtx'
                >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler

unmdize :: String -> String
unmdize s = take (length s - 3) s

dropPrefix :: String -> String -> String
dropPrefix s = drop $ length s

--------------------------------------------------------------------------------
postCtx :: Context String
postCtx =
    dateField "date" "%B %e, %Y" `mappend`
    defaultContext

pluginsCtx :: Bool -> Context String
pluginsCtx isPrep = listField "plugins" defaultContext (loadAll $ "text/plugins/*.md" .&&. verPred) <> defaultContext
    where verPred | isPrep = hasVersion "preprocess"
                  | otherwise = hasNoVersion
