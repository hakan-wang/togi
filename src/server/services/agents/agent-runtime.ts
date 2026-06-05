import https from "node:https";
import { zodTextFormat } from "openai/helpers/zod";
import type { z } from "zod";

export const shouldUseOpenAiAgents = () => Boolean(process.env.OPENAI_API_KEY);

type OpenAiResponsesBody = {
  output?: Array<{
    type: string;
    content?: Array<{
      type: string;
      text?: string;
    }>;
  }>;
  error?: {
    message?: string;
  } | null;
};

const postToOfficialOpenAi = async (body: unknown): Promise<OpenAiResponsesBody> => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY is required for live inference");

  const payload = JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const request = https.request(
      new URL("https://api.openai.com/v1/responses"),
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload)
        }
      },
      (response) => {
        let data = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          data += chunk;
        });
        response.on("end", () => {
          const parsed = JSON.parse(data) as OpenAiResponsesBody;
          if (response.statusCode && response.statusCode >= 400) {
            reject(new Error(parsed.error?.message ?? `OpenAI request failed with status ${response.statusCode}`));
            return;
          }
          resolve(parsed);
        });
      }
    );

    request.on("error", reject);
    request.write(payload);
    request.end();
  });
};

const outputTextFromResponse = (response: OpenAiResponsesBody) => {
  for (const item of response.output ?? []) {
    for (const content of item.content ?? []) {
      if (content.type === "output_text" && content.text) return content.text;
    }
  }
  return null;
};

export const runStructuredAgent = async <T extends z.AnyZodObject>(config: {
  name: string;
  instructions: string;
  model: string;
  outputType: T;
  input: unknown;
}): Promise<z.infer<T>> => {
  const result = await postToOfficialOpenAi({
    model: config.model,
    instructions: config.instructions,
    input: JSON.stringify(config.input),
    text: {
      format: zodTextFormat(config.outputType, config.name.replaceAll(/\W+/g, "_").toLowerCase())
    }
  });

  const outputText = outputTextFromResponse(result);
  if (!outputText) {
    throw new Error(`${config.name} did not return structured output`);
  }

  return config.outputType.parse(JSON.parse(outputText));
};
