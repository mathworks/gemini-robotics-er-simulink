"""
geminiClient.py
---------------
Python bridge to Gemini Robotics ER for robot perception.
Called from MATLAB via py.importlib / py.geminiClient.GeminiClient().

Pure transport layer — no prompt construction or post-processing here.
All prompts are assembled by the MATLAB GeminiERBase subclasses
(GeminiERPlan / GeminiERVerify) before being passed in.
Box coordinate rescaling (0–1000 → pixels) is done on the MATLAB side.

Public interface
----------------
call(images, user_prompt, system_instruction=None, thinking_budget=0)
    Send one or more images with a user message.
    images: list of np.ndarray (uint8 RGB, shape H×W×3).
            Multiple images are labeled "Image 1:", "Image 2:", ...
            A single image is passed without a label.
    Returns the raw JSON string from Gemini, markdown fences stripped.
    thinking_budget: 0 = no thinking (fastest); -1 = unlimited.
"""

import io
import re

import numpy as np
from PIL import Image
from google import genai
from google.genai import types


MODEL = "gemini-robotics-er-1.6-preview"


class GeminiClient:
    def __init__(self, api_key: str):
        self._client = genai.Client(api_key=str(api_key))

    def call(self, images: list, user_prompt: str,
             system_instruction: str = None, thinking_budget: int = 0) -> str:
        """
        Send one or more images with a user message.

        Parameters
        ----------
        images : list of np.ndarray
            One or more uint8 RGB images of shape (H, W, 3).
            Multiple images are prefixed with "Image 1:", "Image 2:", ...
        user_prompt : str
            Task instruction assembled by the MATLAB caller.
        system_instruction : str, optional
            Stable context (role + scenario + format schema).
        thinking_budget : int, optional
            0 = no thinking (fastest); -1 = unlimited.

        Returns
        -------
        str
            Raw JSON string from Gemini, markdown fences stripped.
        """
        label = len(images) > 1
        contents = []
        for i, img in enumerate(images):
            if label:
                contents.append(f"Image {i + 1}:")
            contents.append(types.Part.from_bytes(
                data=self._encode_image(img), mime_type="image/png"))
        contents.append(user_prompt)

        config = types.GenerateContentConfig(
            temperature=0.0,
            thinking_config=types.ThinkingConfig(thinking_budget=thinking_budget),
            system_instruction=system_instruction or None,
        )
        response = self._client.models.generate_content(
            model=MODEL,
            contents=contents,
            config=config,
        )
        raw = response.text.strip()
        return re.sub(r"^```[a-z]*\n?|\n?```$", "", raw, flags=re.MULTILINE).strip()

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _encode_image(self, img_numpy: np.ndarray) -> bytes:
        """Convert numpy array to PNG bytes."""
        img = Image.fromarray(np.array(img_numpy, dtype=np.uint8))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()
