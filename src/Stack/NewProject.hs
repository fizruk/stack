{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
module Stack.NewProject where

import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Logger
import           Data.List              (intercalate)
import           Data.Monoid
import qualified Data.Text              as T
import           Stack.Types.StackT
import           System.Directory
import           System.Exit
import           System.FilePath
import           System.Process

data NewProjectDependency =
  NewProjectDependency
  { name    :: T.Text
  , version :: Maybe T.Text }
  deriving (Eq,Show)

data NewProjectArgs =
  NewProjectArgs
  { npaProjectName  :: T.Text
  , npaTemplateName :: T.Text
  , npaDependencies :: [NewProjectDependency] }
  deriving (Eq,Show)

-- | Create a new project
create :: NewProjectArgs -> StackLoggingT IO ()
create args@NewProjectArgs{..} = do
  $logInfo $ "Creating new project named " <> npaProjectName <> " using template '" <> npaTemplateName <> "'."

  defaultTemplate args

  $logInfo "stack new complete."

defaultTemplate :: NewProjectArgs -> StackLoggingT IO ()
defaultTemplate args@NewProjectArgs{..} = do
  let directoryName = T.unpack npaProjectName

  $logInfo "Creating default template"

  $logInfo "Creating directory"
  alreadyExists <- liftIO $ doesDirectoryExist directoryName
  when alreadyExists $ error ("Directory " <> directoryName <> " already exists.")

  liftIO $ createDirectory directoryName

  $logInfo "Running cabal"
  (_, _, _, ph) <- liftIO $
    createProcess (proc "cabal" ["init", "--main-is=Main.hs", "--source-dir=src"])
                       { delegate_ctlc = True
                       , cwd = Just directoryName }
  cabalExitCode <- liftIO $ waitForProcess ph

  case cabalExitCode of
   ExitFailure code -> error $ "Cabal failed with an exit code of " <> show code
   _ -> return ()

  $logInfo "Verifying license"
  licenseExists <- liftIO $ doesFileExist (directoryName </> "LICENSE")
  when (not licenseExists) $ do
   $logInfo "LICENSE file was not autogenerated - touching one now"
   liftIO $ writeFile (directoryName </> "LICENSE") "\n"

  $logInfo "Creating Main module"
  liftIO $ createDirectory (directoryName </> "src")
  liftIO $ writeFile (directoryName </> "src" </> "Main.hs")
         $ T.unpack $ T.intercalate "\n"
             [ "module Main where"
             , ""
             , "main :: IO ()"
             , "main = putStrLn \"Hello, " <> npaProjectName <> "\""
             , ""]

  $logInfo "Creating stack.yaml file"
  liftIO $ writeFile (directoryName </> "stack.yaml") (createStackYaml args)


  $logInfo "Running stack build" -- TODO: Actually call into build
  (_, _, _, stackProcessHandle) <- liftIO $
    createProcess (proc "stack" ["build"])
                       { delegate_ctlc = True
                       , cwd = Just directoryName }
  stackExitCode <- liftIO $ waitForProcess stackProcessHandle

  case stackExitCode of
   ExitFailure code -> error $ "Stack build failed with an exit code of " <> show code
   _ -> return ()

  return ()

createStackYaml :: NewProjectArgs -> String
createStackYaml NewProjectArgs{..} =
  let resolver = "lts-2.9"
      packages = ["."]

      asPackageEntry x = "- " <> x <> "\n"
  in "resolver: " <> resolver <> "\n" <>
     "packages: " <> "\n" <> intercalate "\n" (map asPackageEntry packages)
