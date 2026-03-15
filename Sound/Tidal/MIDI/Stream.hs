module Sound.Tidal.MIDI.Stream (
  startMidiStream,
  attachMidi,
) where

import Control.Concurrent.MVar
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)

import qualified Sound.Tidal.Clock as Clock
import qualified Sound.Tidal.Link as Link
import Sound.Tidal.Config (Config, toClockConfig)
import Sound.Tidal.Pattern
import Sound.Tidal.Stream.Process (playStack)
import Sound.Tidal.Stream.Types (Stream (..), PlayMap)

import Sound.Tidal.MIDI.Output

-- | Start a Tidal 'Stream' that sends MIDI note events instead of OSC.
-- The returned 'Stream' is compatible with all standard tidal functions
-- ('d1', 'hush', 'cps', etc.).
--
-- Example:
--
-- > stream <- startMidiStream "My Synth" defaultConfig
-- > let d1 = streamReplace stream "d1"
-- > d1 $ note "0 3 7" # velocity "0.8"
startMidiStream :: String  -- ^ PortMidi output device name
                -> Config  -- ^ Tidal config (use 'defaultConfig' to start)
                -> IO Stream
startMidiStream deviceName config = do
  eOut <- openMidiOutput deviceName
  out  <- case eOut of
    Left  err -> error err
    Right o   -> return o
  outMV     <- newMVar out
  sMapMV    <- newMVar Map.empty
  pMapMV    <- newMVar Map.empty
  globalFMV <- newMVar id
  clockRef  <- Clock.clocked (toClockConfig config)
                              (midiTick outMV sMapMV pMapMV globalFMV)
  return Stream
    { sConfig    = config
    , sStateMV   = sMapMV
    , sClockRef  = clockRef
    , sListen    = Nothing
    , sPMapMV    = pMapMV
    , sGlobalFMV = globalFMV
    , sCxs       = []
    }

-- | Attach a MIDI output to an existing tidal 'Stream'.
-- The MIDI output will follow the same patterns as the stream, so the
-- standard 'd1', 'd2', 'hush', 'cps' etc. functions drive MIDI automatically.
--
-- Typical boot usage:
--
-- > tidalInst <- mkTidal
-- > attachMidi "IAC Driver Bus 1" tidalInst
-- > instance Tidally where tidal = tidalInst
attachMidi :: String -> Stream -> IO ()
attachMidi deviceName tidalStream = do
  eOut <- openMidiOutput deviceName
  out  <- case eOut of
    Left  err -> error err
    Right o   -> return o
  outMV  <- newMVar out
  sMapMV <- newMVar Map.empty
  _      <- Clock.clocked (toClockConfig (sConfig tidalStream))
                          (midiTick outMV sMapMV (sPMapMV tidalStream) (sGlobalFMV tidalStream))
  return ()

-- Internal tick handler, called by the Tidal clock on every arc.
midiTick :: MVar MidiOutput
         -> MVar ValueMap
         -> MVar PlayMap
         -> MVar (ControlPattern -> ControlPattern)
         -> Clock.TickAction
midiTick outMV stateMV playMV globalFMV (st, end) nudge cconf cref (ss, _) = do
  out      <- readMVar outMV
  pMap     <- readMVar playMV
  sGlobalF <- readMVar globalFMV
  bpm      <- Clock.getTempo ss
  let cps          = Clock.beatToCycles cconf (fromRational bpm) / 60
      cycleLatency = toRational (nudge / cps)
      patstack     = rotR cycleLatency $ sGlobalF $ playStack pMap
  sMap <- takeMVar stateMV
  let sMap'         = Map.insert "_cps" (VF cps) sMap
      es            = filter eventHasOnset $
                        query patstack (State { arc = Arc st end, controls = sMap' })
      (sMap'', es') = resolveState sMap' es
  putMVar stateMV sMap''
  let al = Clock.rAbletonLink cref
  notes <- mapM (toNote cconf ss) es'
  sendNotes out al notes

toNote :: Clock.ClockConfig -> Link.SessionState -> Event ValueMap
       -> IO (Int, Int, Int, Link.Micros, Link.Micros)
toNote cconf ss e = do
  let vm      = value e
      wope    = wholeOrPart e
      onBeat  = Clock.cyclesToBeat cconf (realToFrac (start wope))
      offBeat = Clock.cyclesToBeat cconf (realToFrac (stop  wope))
  onLink  <- Clock.timeAtBeat cconf ss onBeat
  offLink <- Clock.timeAtBeat cconf ss offBeat
  return (chanFromVM vm, noteFromVM vm, velFromVM vm, onLink, offLink)

-- ---------------------------------------------------------------------------
-- ValueMap helpers

noteFromVM :: ValueMap -> Int
noteFromVM vm = clamp 0 127 $ case Map.lookup "n" vm of
  Just (VN (Note n)) -> round n + 60
  Just (VF n)        -> round n + 60
  Just (VI n)        -> n + 60
  _                  -> fromMaybe 60 $ do
    v <- Map.lookup "note" vm
    case v of
      VN (Note n) -> Just (round n + 60)
      VF n        -> Just (round n)
      VI n        -> Just n
      _           -> Nothing

velFromVM :: ValueMap -> Int
velFromVM vm = clamp 0 127 $ case Map.lookup "velocity" vm of
  Just (VF v) -> round (v * 127)
  _           -> case Map.lookup "gain" vm of
    Just (VF g) -> round (g * 127)
    _           -> 100

chanFromVM :: ValueMap -> Int
chanFromVM vm = clamp 1 16 $ case Map.lookup "channel" vm of
  Just (VI c) -> c
  Just (VF c) -> round c
  _           -> 1

clamp :: Int -> Int -> Int -> Int
clamp lo hi = max lo . min hi
