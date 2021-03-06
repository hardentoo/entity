--module AsciiShooter.Terminal where

import UI.NCurses hiding (Key, Color)
import Control.Concurrent.STM
import Control.Concurrent
import Control.Monad.IO.Class
import Control.Monad
import Data.Text hiding (map, take, reverse)
import Data.Array.Diff
import Data.Set (Set)
import qualified Data.Set as Set
import Debug.Trace

data Color = Red deriving (Eq, Ord, Show)
data Key = KeyUp | KeyDown | KeyLeft | KeyRight | KeyFire deriving (Eq, Ord, Show)
type Picture = DiffArray (Int, Int) (Char, Color)
type Position = (Int, Int)
data Rotaion = North | South | East | West
type Tank = (Position, Rotaion)

main = runCurses $ do
    window <- defaultWindow
    tankVar <- liftIO (newTVarIO ((10, 10), North))
    keyChan <- liftIO newTChanIO
    liftIO $ forkIO (controller tankVar keyChan)
    drawListenLoop window tankVar keyChan

background :: Integral a => a -> a -> DiffArray (Int, Int) (Char, Color)     
background width height = 
    listArray ((0, 0), (fromIntegral width - 1, fromIntegral height - 2)) (repeat (' ', Red))

draw :: Window -> (Color -> ColorID) -> Picture -> Curses ()
draw window colors picture = do
    updateWindow window $ do
        forM_ (assocs picture) $ \((x, y), (character, color)) -> do
            moveCursor (fromIntegral y) (fromIntegral x)
            setColor (colors color)
            drawText (pack ([character]))
    render


listener :: Window -> TChan Key -> Curses ()
listener window keyChan = do
    event <- getEvent window (Just 0)
    liftIO $ atomically $ do
        case event of
            Just (EventSpecialKey key) -> 
                case key of
                    KeyUpArrow -> writeTChan keyChan KeyUp
                    KeyDownArrow -> writeTChan keyChan KeyDown
                    KeyLeftArrow -> writeTChan keyChan KeyLeft
                    KeyRightArrow -> writeTChan keyChan KeyRight
                    _ -> return ()
            Just (EventCharacter character) -> 
                case character of
                    ' ' -> writeTChan keyChan KeyFire
                    _ -> return ()
            _ -> return ()


drawListenLoop :: Window -> TVar Tank -> TChan Key -> Curses ()
drawListenLoop window tankVar keyChan = do 
    red <- newColorID ColorRed ColorBlack 1
    loop window (const red)
    where
        loop :: Window -> (Color -> ColorID) -> Curses ()
        loop window colors = do
            (rows, columns) <- screenSize
            let picture = background columns rows
            tank <- liftIO (readTVarIO tankVar)
            picture <- return $ drawTank picture tank
            draw window colors picture
            listener window keyChan
            loop window colors


controller :: TVar Tank -> TChan Key -> IO ()
controller tankVar keyChan = loop 
    where
        loop = do
            tank <- atomically $ do
                key <- readTChan keyChan
                ((x, y), _) <- readTVar tankVar
                let tank = case key of
                        KeyUp -> ((x, y - 1), North)
                        KeyDown -> ((x, y + 1), South)
                        KeyLeft -> ((x - 1, y), West)
                        KeyRight -> ((x + 1, y), East)
                writeTVar tankVar tank
            loop

translateSprite (x, y) sprite = 
    map (first (\(x', y') -> (x + x', y + y'))) sprite
        
        
tankAsciiNorth = [
    " || ",
    "¤||¤",
    "¤()¤",
    "¤--¤"]

tankAsciiEast = [
    "¤¤¤ ",
    "|o==",
    "¤¤¤ "]
            
tankSprite North = toSprite tankAsciiNorth
tankSprite South = toSprite (reverse tankAsciiNorth)
tankSprite West = toSprite (map reverse tankAsciiEast)
tankSprite East = toSprite tankAsciiEast

toSprite :: [String] -> [((Int, Int), (Char, Color))]
toSprite lines = toSpriteLines 0 lines
    where
        toSpriteLines :: Int -> [String] -> [((Int, Int), (Char, Color))]
        toSpriteLines row [] = []
        toSpriteLines row (line : lines) = toSpriteLine 0 row line ++ toSpriteLines (row + 1) lines

        toSpriteLine :: Int -> Int -> String -> [((Int, Int), (Char, Color))]
        toSpriteLine column row [] = []
        toSpriteLine column row (char : line) = ((column, row), (char, Red)) : toSpriteLine (column + 1) row line
            
drawTank :: Picture -> Tank -> Picture
drawTank picture (location, rotation) = 
    let sprite = translateSprite location (tankSprite rotation) in
    picture // sprite
    


first :: (a -> b) -> (a, c) -> (b, c)
first f (a, c) = (f a, c)

second :: (b -> c) -> (a, b) -> (a, c)
second f (a, b) = (a, f b)

