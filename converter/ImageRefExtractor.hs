{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE RecordWildCards #-}

module ImageRefExtractor(extract) where

import qualified Data.Text as T
import qualified Data.Text.Read as TR
import qualified Data.IntMap as IM
import qualified Data.HashMap.Lazy as M
import qualified Data.Vector as V
import Control.Arrow
import Data.Maybe
import Data.Monoid
import Data.List

import Node

data ImageRefType = Side | Inline deriving (Eq, Ord, Show)

data ImageRef = ImageRef {
        refType :: ImageRefType,
        refNid :: Int,
        refTitle :: Maybe T.Text,
        refSize :: Maybe (Int, Int)
    } deriving (Eq, Ord, Show)

extract :: V.Vector Node -> T.Text -> (T.Text, [ImageRef])
extract (buildNodeMap -> ns) t = mapAccumL (\acc -> first (acc <>) . extractChunk ns) h rest
    where (h:rest) = T.splitOn "[img_assist|" t

imageRef :: M.HashMap T.Text T.Text -> ImageRef
imageRef flags = ImageRef (typ $ M.lookup "align" flags) (readInt $ flags M.! "nid") title size
    where typ (Just "inline") = Side
          typ Nothing = Inline
          typ (Just t) = error $ "Unknown align: " ++ T.unpack t
          title = do
                v <- M.lookup "title" flags
                if T.null v then Nothing else return v
          size = do
                w <- M.lookup "width" flags
                h <- M.lookup "height" flags
                return (readInt w, readInt h)

readInt :: T.Text -> Int
readInt (TR.decimal -> Right (n, _)) = n
readInt t = error $ "Cannot read text as integer: " ++ T.unpack t

extractChunk :: IM.IntMap Node -> T.Text -> (T.Text, ImageRef)
extractChunk imgs t | refType ref == Side = (rest, ref)
                    | otherwise = (ref2text imgs ref <> rest, ref)
    where (ref, rest) = (imageRef . parseAssist) *** T.tail $ T.breakOn "]" t

ref2text :: IM.IntMap Node -> ImageRef -> T.Text
ref2text nodes ImageRef { .. } = "![" <> title' <> "](" <> imagePath <> " \"" <> title' <> "\")" 
    where title' = fromMaybe T.empty refTitle
          Node { contents = ImageContents { .. }, .. } = nodes IM.! refNid

buildNodeMap :: V.Vector Node -> IM.IntMap Node
buildNodeMap = IM.fromList . V.toList . V.map (\n -> (nid n, n)) . V.filter ((== Image) . typ)

parseAssist :: T.Text -> M.HashMap T.Text T.Text
parseAssist = M.fromList . map (second T.tail . T.breakOn "=") . T.splitOn "|"