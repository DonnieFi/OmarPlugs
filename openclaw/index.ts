import { Type } from "typebox";
import { defineFeatureContract } from "openclaw/plugin-sdk/feature-contract";
import { defineFeaturePlugin } from "openclaw/plugin-sdk/feature-plugin";
import { ErrorCodes, errorShape } from "openclaw/plugin-sdk/gateway-runtime";
import { defaultLanarchyStateDir } from "./src/state-reader.js";
import { readLanarchyDashboardSnapshot } from "./src/contract.js";

const contract = defineFeatureContract({
  pluginId: "lanarchy",
  operations: {
    snapshot: {
      kind: "query",
      description: "Read the bounded Lanarchy homelab health snapshot.",
      input: Type.Object({}, { additionalProperties: false }),
      output: Type.Record(Type.String(), Type.Unknown()),
    },
  },
  events: {},
});

export default defineFeaturePlugin({
  contract,
  name: "Lanarchy",
  description: "Read-only OpenClaw dashboard for Lanarchy homelab health and topology.",
  setup(api) {
    const stateDir = defaultLanarchyStateDir();

    // The native widget uses this directly. The feature operation below keeps
    // the same bounded read available through OpenClaw's typed session-action
    // transport, without making the browser read a file or start a probe.
    api.registerGatewayMethod(
      "lanarchy.snapshot",
      async ({ params, respond }) => {
        if (
          params !== undefined &&
          (typeof params !== "object" || params === null || Array.isArray(params))
        ) {
          respond(false, undefined, {
            code: ErrorCodes.INVALID_REQUEST,
            message: "Lanarchy snapshot params must be an object",
          });
          return;
        }
        try {
          respond(true, readLanarchyDashboardSnapshot(stateDir));
        } catch (error) {
          // Do not echo paths, raw JSON, or parser details into the Gateway
          // response. The dashboard only needs to know that the read failed.
          const message = error instanceof Error ? error.message : "Lanarchy snapshot unavailable";
          respond(false, undefined, errorShape(ErrorCodes.UNAVAILABLE, message));
        }
      },
      { scope: "operator.read" },
    );

    return {
      snapshot: async () => readLanarchyDashboardSnapshot(stateDir),
    };
  },
});
