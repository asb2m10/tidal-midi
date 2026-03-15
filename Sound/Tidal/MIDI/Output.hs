module Sound.Tidal.MIDI.Output (
  MidiOutput(..),
  openMidiOutput,
  closeMidiOutput,
  writeMidiEvents,
) where

import Foreign.C.Types (CULong)
import qualified Sound.PortMidi as PM

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

-- | Write a pre-sorted batch of PortMidi events to the output stream.
-- Callers are responsible for sorting by timestamp before calling.
writeMidiEvents :: MidiOutput -> [PM.PMEvent] -> IO ()
writeMidiEvents _   []     = return ()
writeMidiEvents out events = PM.writeEvents (pmStream out) events >> return ()
