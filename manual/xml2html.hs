import Text.Docutils.CmdLine

import System.Directory
import System.FilePath

import Control.Arrow
import Control.Monad (when)

import Text.Docutils.Util
import Text.Docutils.Writers.HTML
import Text.Docutils.Transformers.Haskell

import Text.XML.HXT.Core hiding (when)

import Crypto.Hash.MD5
import qualified Data.ByteString.Char8 as B
import Data.ByteString.Base16

import Diagrams.Backend.Cairo
import Build

main :: IO ()
main = do
  (modMap, nameMap) <- buildPackageMaps 
                       [ "diagrams-core"
                       , "diagrams-lib"
                       , "diagrams-cairo"
                       ]
  docutilsCmdLine (diagramsManual modMap nameMap)

diagramsManual modMap nameMap =
  doTransforms [ linkifyHackage
               , linkifyModules modMap
               , highlightInlineHS
               , highlightBlockHS
               , linkifyHS nameMap modMap
               , compileDiagrams
               , compileDiagramsLHS
               ]
  >>> xml2html
  >>> doTransforms [ styleFile "default.css"
                   , styleFile "syntax.css"
                   ]
  
compileDiagrams :: XmlT (IOSLA (XIOState ()))
compileDiagrams = onElemA "raw" [("format", "dia")] $ 
  eelem "div"
    += attr "class" (txt "exampleimg")
    += compileDiaArr

-- | Compile code blocks intended to generate both a diagram and the
--   syntax highlighted code.
compileDiagramsLHS :: XmlT (IOSLA (XIOState ()))
compileDiagramsLHS = onElemA "raw" [("format", "dia-lhs")] $
  eelem "div"
    += attr "class" (txt "dia-lhs")
    += (compileDiaArr <+> highlightBlockHSArr)

compileDiaArr :: (ArrowXml (~>), ArrowIO (~>)) => XmlT (~>)
compileDiaArr =
  getChildren >>>
  getText >>>
  arrIO compileDiagram >>>
  eelem "center" += 
    (eelem "img" 
       += attr "src" mkText
    )

-- | Compile the literate source code of a diagram to a .png file with
--   a file name given by a hash of the source code contents
compileDiagram :: String -> IO String
compileDiagram src = do
  let fileBase = B.unpack . encode . hash . B.pack $ src
      imgFile = "images" </> fileBase <.> "png"
  ex <- doesFileExist imgFile
  when (not ex) $ do
    putStrLn $ "Generating " ++ imgFile ++ "..."
    buildDiagram src (CairoOptions imgFile (PNG (200,200)))
  return imgFile
