"""
Multi-modal emotion detection package for Sakinah.

Combines:
- Face emotion (HSEmotion / AffectNet-8) — visual signal from camera
- Text emotion (DistilRoBERTa-emotion + Groq translate) — semantic signal from journal text
- Confidence-weighted fusion -> mapped to Sakinah's 15-emotion taxonomy

The face/text models are loaded lazily on first request and cached for the
process lifetime, so cold start is fast and warm requests are sub-second.
"""
