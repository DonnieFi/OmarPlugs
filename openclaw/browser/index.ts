import { defineControlUiPlugin } from "openclaw/plugin-sdk/control-ui";
import { createLanarchyWidget } from "./widget.js";
import "./styles.css";

export default defineControlUiPlugin({
  id: "lanarchy",
  activate(host) {
    return host.ui.registerWidget({
      id: "mesh",
      label: "Lanarchy mesh",
      mount: createLanarchyWidget(host),
    });
  },
});
