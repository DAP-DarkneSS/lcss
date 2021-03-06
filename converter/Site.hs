{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NamedFieldPuns #-}

module Site(PagesSet, convertSite) where

import qualified Data.HashMap.Strict as M
import qualified Data.Text as T
import GHC.Generics
import Data.Hashable
import Data.Foldable
import Data.Maybe
import Data.Char
import Data.Default
import Data.Monoid
import Control.Arrow
import Data.String.Interpolate.IsString
import qualified Text.Pandoc.Readers.HTML as P
import qualified Text.Pandoc.Writers.Markdown as P
import qualified Text.Pandoc.Error as P
import qualified Text.Pandoc.Options as P
import qualified Data.Time.Format as Time
import qualified Data.Time.Clock.POSIX as Time

import Node
import ImageRefExtractor
import LinksRewriter

data RootCategory = Other
        | News
        | Plugins
        | UserGuide
        | Development
        | Concepts
        deriving (Show, Eq, Ord, Generic)

instance Hashable RootCategory

data Category = Category RootCategory [T.Text] deriving (Show, Eq, Ord, Generic)

instance Hashable Category


data NodeWRefs = NodeWRefs {
        node :: Node,
        imageRefs :: [ImageRef]
    } deriving (Show, Eq)


data Site t = Site {
        pages :: M.HashMap Category [t]
    } deriving (Show, Eq)

instance Functor Site where
    fmap f s = s { pages = (f <$>) <$> pages s }

type PagesSet = [([String], T.Text)]


convertSite :: Foldable t => t Node -> PagesSet
convertSite = toPagesSet . nodes2site

mapPagesWithCat :: (Category -> t -> t') -> Site t -> Site t'
mapPagesWithCat f s = s { pages = M.mapWithKey (\c -> (f c <$>)) $ pages s }


nodes2site :: Foldable t => t Node -> Site NodeWRefs
nodes2site ns = enrichMetadata ns <$> mapPagesWithCat catMetadata site
    where fixSubtyp (Category c ts) = Category c $ ts >>= subtyp c
          site = Site (M.fromListWith (++) $ map (fixSubtyp . nodeCat &&& return) $ filter ((/= Image) . typ) $ toList ns)

catMetadata :: Category -> Node -> Node
catMetadata (Category Plugins _) n@Node { contents = TextContents { body }, title } = key $ addMetadata "shortdescr" (shortDescr title body) n
    where key | T.toLower title `elem` ["advancednotifications", "aggregator", "azoth", "bittorrent", "lackman", "lmp", "monocle", "poshuku", "sb2", "summary"] = addMetadata "keyplugin" "1"
              | otherwise = id
catMetadata _ n = n

shortDescr :: T.Text -> T.Text -> T.Text
shortDescr title body = sentence''''
    where sentence = T.strip $ T.takeWhile (/= '.') $ stripTags body
          sentence' = fromMaybe sentence $ T.stripPrefix title sentence
          sentence'' = T.dropWhile (not . isAlpha) sentence'
          sentence''' = T.strip $ fromJust $ msum $ map (`T.stripPrefix` sentence'') ["is a plugin", "is a", "is the", "plugin"] <> [Just sentence'']
          sentence'''' = T.replace ":" "':'" sentence'''

stripTags :: T.Text -> T.Text
stripTags s | Just True <- (<) <$> openPos <*> dotPos = stripTags $ T.drop (fromJust (T.findIndex (== ']') s) + 1) s
            | otherwise = s
    where dotPos = T.findIndex (== '.') s
          openPos = T.findIndex (== '[') s


enrichMetadata :: Foldable t => t Node -> Node -> NodeWRefs
enrichMetadata ns = uncurry NodeWRefs . extractImageRefs ns

nodeCat :: Node -> Category
nodeCat (typ -> Story) = Category News []
nodeCat (url -> t) = fromJust $ msum $ map (uncurry root) roots  ++ [Just $ Category Other []]
    where root r c |  r `T.isPrefixOf` t = Just $ Category c [T.drop (T.length r + 1) t]
                   | otherwise = Nothing
          roots = [("plugins", Plugins), ("user-guide", UserGuide), ("development", Development), ("concepts", Concepts)]

subtyp :: RootCategory -> T.Text -> [T.Text]
subtyp c t | Just ss <- lookup c cs
           , Just s <- find ((`T.isPrefixOf` t) . (`T.snoc` '-')) ss = [s]
           | otherwise = []
    where cs = [(Plugins, ["azoth", "aggregator", "lmp", "poshuku", "blasq"])]

data ConvContext = ConvContext {
        id2node :: M.HashMap Int Node
    } deriving (Eq, Show)

toPagesSet :: Site NodeWRefs -> PagesSet
toPagesSet s = concatMap (catToPagesSet ctx) $ M.toList $ pages s
    where ctx = ConvContext $ M.fromList $ map ((\n -> (nid n, n)) . node) $ concat $ M.elems $ pages s

catToPagesSet :: ConvContext -> (Category, [NodeWRefs]) -> PagesSet
catToPagesSet ctx (cat2path -> path, ns) = map (nodePath &&& node2contents ctx) ns
    where nodePath n = path ++ [mkFilename (node n) ++ ".md"]
          mkFilename n | not $ T.null $ url n = T.unpack $ url n
                       | otherwise = "node-" ++ show (nid n)

cat2path :: Category -> [String]
cat2path (Category Other s) = T.unpack <$> s
cat2path (Category r s) = (toLower <$> show r) : (T.unpack <$> s)

node2contents :: ConvContext -> NodeWRefs -> T.Text
node2contents ctx NodeWRefs { node = Node { contents = TextContents { .. }, .. }, .. } = T.strip fullS
    where convert = T.pack . P.writeMarkdown writeOpts . P.handleError . P.readHtml readOpts . rewriteLinks (id2node ctx) . T.unpack . fixBreaks . fixCode
          readOpts = def { P.readerParseRaw = True }
          writeOpts = def { P.writerHighlight = True }
          metadataLines = T.unlines $ ((\(k, v) -> [i|#{k}: #{v}|]) <$>) $ M.toList metadata
          published = Time.formatTime Time.defaultTimeLocale (Time.iso8601DateFormat $ Just "%H:%M:%S") $ Time.posixSecondsToUTCTime $ realToFrac timestamp
          fullS = [i|
---
title: #{title}
tags: #{T.intercalate ", " tags}
published: #{published}
#{metadataLines}
---

#{s}
|]
          s | T.null teaser || teaser `T.isPrefixOf` body = convert body
            | otherwise = convert teaser <> "\n<!--more-->\n" <> convert body
node2contents _ _ = error "unsupported node type"

fixBreaks :: T.Text -> T.Text
fixBreaks =  T.replace m verb . T.replace "\n\n" "<br/><br/>" . T.replace verb m
    where m = "__MEH__"
          verb = "\n\n<h"

fixCode :: T.Text -> T.Text
fixCode = T.replace "\n<code" "\n<pre" .
          T.replace "\t<code" "\t<pre" .
          T.replace "\t<code>" "\t<pre type=\"c++\">" .
          T.replace "\t<code>" "\t<pre type=\"c++\">" .
          T.replace "\t</code>" "\t</pre>" .
          T.replace "\n</code>" "\n</pre>"
