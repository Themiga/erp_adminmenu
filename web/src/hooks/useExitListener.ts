import {useEffect, useRef} from "react";
import {noop} from "../utils/misc";
import {fetchNui, sendGameAction} from "../utils/fetchNui";
import {getBridgeMode} from "../utils/bridge";

type FrameVisibleSetter = (bool: boolean) => void

const LISTENED_KEYS = ["Escape"]

export const useExitListener = (visibleSetter: FrameVisibleSetter) => {
  const setterRef = useRef<FrameVisibleSetter>(noop)

  useEffect(() => {
    setterRef.current = visibleSetter
  }, [visibleSetter])

  useEffect(() => {
    const keyHandler = (e: KeyboardEvent) => {
      if (!LISTENED_KEYS.includes(e.code)) return;

      setterRef.current(false)

      if (getBridgeMode() === 'dui') {
        void sendGameAction('close')
      } else {
        void fetchNui('hideFrame')
      }
    }

    window.addEventListener("keydown", keyHandler)
    return () => window.removeEventListener("keydown", keyHandler)
  }, []);
}