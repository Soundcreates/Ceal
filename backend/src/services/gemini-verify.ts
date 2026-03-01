/**
 * AfterMath Backend — Gemini Flash 2.5 disaster image verification.
 *
 * Receives an image buffer, sends it to Gemini Vision, and returns a
 * structured classification: is it a real disaster, what category,
 * estimated severity, confidence, and any red flags.
 *
 * The system prompt is server-side only and never influenced by user input.
 */

import { GoogleGenerativeAI, type Part } from '@google/generative-ai';
import { env } from '../config.js';
import { logger } from '../logger.js';
import type { GeminiVerificationResult, DisasterCategory } from '../models/disaster-report.js';

const VALID_CATEGORIES: DisasterCategory[] = [
  'fire', 'flood', 'accident', 'infrastructure', 'medical', 'other',
];

const SYSTEM_PROMPT = `You are a disaster image verification system for a civic safety platform.
Your job is to analyze a photo and determine:
1. Whether it shows a REAL disaster, emergency, or civic hazard.
2. What category it belongs to.
3. How severe it is (1-5 scale).
4. Your confidence in the assessment (0-1).

CATEGORIES (pick exactly one):
- fire: fires, smoke, burning structures
- flood: flooding, waterlogging, water damage
- accident: vehicle accidents, collapses, industrial accidents
- infrastructure: damaged roads, broken bridges, fallen power lines, structural damage
- medical: medical emergencies visible in scene (mass casualty, etc.)
- other: legitimate emergencies not fitting above categories

SEVERITY SCALE:
1 = Minor (small, localized, low risk)
2 = Moderate (some property damage or risk)
3 = Significant (clear danger, multiple affected)
4 = Severe (major destruction, immediate danger to life)
5 = Critical (catastrophic, mass casualties possible)

RED FLAGS to check for:
- AI-generated images (perfect symmetry, impossible lighting, artifacts)
- Stock photos (watermarks, unusually perfect composition)
- Screenshots of other apps/websites
- Photos of screens/monitors
- Irrelevant content (selfies, food, memes, text-only images)
- Clearly old/recycled disaster photos

You MUST respond with valid JSON only. No markdown, no explanation outside the JSON.`;

const USER_PROMPT_TEMPLATE = `Analyze this image and determine if it shows a real disaster or emergency.

{DESCRIPTION_BLOCK}

Respond with this exact JSON structure:
{
  "isReal": true/false,
  "category": "fire|flood|accident|infrastructure|medical|other",
  "severity": 1-5,
  "confidence": 0.0-1.0,
  "reasoning": "Brief explanation",
  "flags": ["list", "of", "red", "flags", "if", "any"]
}`;

/**
 * Verify a disaster image using Gemini Flash 2.5 Vision.
 *
 * Returns null if Gemini is unavailable (no API key) — the report
 * will be stored with verification_status='pending' for manual review.
 */
export async function verifyDisasterImage(
  imageBuffer: Buffer,
  mimeType: string,
  lat: number,
  lon: number,
  userDescription?: string,
): Promise<GeminiVerificationResult | null> {
  if (!env.GEMINI_API_KEY) {
    logger.warn('GEMINI_API_KEY not set — skipping LLM verification');
    return null;
  }

  const genAI = new GoogleGenerativeAI(env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

  const descBlock = userDescription
    ? `User description: "${userDescription}"`
    : 'No description provided by user.';

  const userPrompt = USER_PROMPT_TEMPLATE.replace('{DESCRIPTION_BLOCK}', descBlock)
    + `\nReported GPS: ${lat.toFixed(6)}, ${lon.toFixed(6)}`;

  const imagePart: Part = {
    inlineData: {
      mimeType,
      data: imageBuffer.toString('base64'),
    },
  };

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: 'user',
          parts: [
            { text: SYSTEM_PROMPT },
            imagePart,
            { text: userPrompt },
          ],
        },
      ],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 1024,
        responseMimeType: 'application/json',
      },
    });

    const response = result.response;
    const text = response.text().trim();

    // Strip markdown code fences if present
    const jsonStr = text
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/i, '')
      .trim();

    const parsed = JSON.parse(jsonStr) as Record<string, unknown>;

    // Validate and clamp the response
    const category = VALID_CATEGORIES.includes(parsed.category as DisasterCategory)
      ? (parsed.category as DisasterCategory)
      : 'other';

    const severity = Math.min(5, Math.max(1, Math.round(Number(parsed.severity) || 3)));
    const confidence = Math.min(1, Math.max(0, Number(parsed.confidence) || 0.5));

    const verification: GeminiVerificationResult = {
      isReal: Boolean(parsed.isReal),
      category,
      severity,
      confidence,
      reasoning: String(parsed.reasoning ?? ''),
      flags: Array.isArray(parsed.flags) ? parsed.flags.map(String) : [],
    };

    logger.info(
      `Gemini verify: isReal=${verification.isReal} cat=${verification.category} ` +
      `sev=${verification.severity} conf=${verification.confidence.toFixed(2)}`,
    );

    return verification;
  } catch (err) {
    logger.error('Gemini verification failed', err);
    return null;
  }
}
