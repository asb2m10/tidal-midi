module Sound.Tidal.MIDI.Output (
  MidiOutput(..),
  openMidiOutput,
  closeMidiOutput,
  sendNotes,
) where

import Data.Bits
import Data.List (sortBy)
import Data.Ord (comparing)
import Foreign.C.Types (CLong, CULong)
import qualified Sound.PortMidi as PM
import qualified Sound.Tidal.Link as Link

data MidiOutput = MidiOutput
  { pmStream :: PM.PMStream
  }

-- | Open a MIDI output device by name.
-- Call 'Sound.Tidal.MIDI.Device.displayOutputDevices' to list available names.
openMidiOutput :: String -> IO (Either String MidiOutput)
openMidiOutput name = do
  _ <- PM.initialize
  count <- PM.countDevices
  devs  <- mapM (\i -> (,) i <$> PM.getDeviceInfo i) [0 .. count - 1]
  let outputs = filter (PM.output . snd) devs
      matches = filter ((== name) . PM.name . snd) outputs
  case matches of
    [] -> do
      let names = map (PM.name . snd) outputs
      return $ Left $
        "MIDI device '" ++ name ++ "' not found.\nAvailable outputs: " ++ show names
    ((devId, _) : _) -> do
      result <- PM.openOutput (fromIntegral devId) 1
      case result of
        Left stream -> return $ Right (MidiOutput stream)
        Right err   -> return $ Left $ "Failed to open MIDI device: " ++ show err

closeMidiOutput :: MidiOutput -> IO ()
closeMidiOutput out = PM.close (pmStream out) >> return ()

-- | Schedule a batch of MIDI note on+off pairs in a single PortMidi write.
-- Timing is sampled once so all notes in the batch share the same reference,
-- which is required for chords to fire simultaneously.
-- Each tuple is (channel 1-16, note 0-127, velocity 0-127, onLink, offLink).
sendNotes :: MidiOutput
          -> Link.AbletonLink
          -> [(Int, Int, Int, Link.Micros, Link.Micros)]
          -> IO ()
sendNotes _   _           []    = return ()
sendNotes out abletonLink notes = do
  linkNow <- Link.clock abletonLink
  pmNow   <- PM.time
  let toPm t  = pmNow + fromIntegral (max 0 ((t - linkNow) `div` 1000)) :: CULong
      toEvents (ch, n, v, onL, offL) =
        [ PM.PMEvent (PM.encodeMsg (PM.PMMsg (0x90 .|. fromIntegral (ch - 1)) (fromIntegral n) (fromIntegral v))) (toPm onL)
        , PM.PMEvent (PM.encodeMsg (PM.PMMsg (0x80 .|. fromIntegral (ch - 1)) (fromIntegral n) 0))               (toPm offL)
        ]
      sorted = sortBy (comparing PM.timestamp) (concatMap toEvents notes)
  _ <- PM.writeEvents (pmStream out) sorted
  return ()
