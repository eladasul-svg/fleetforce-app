import { createElement } from "lwc";
import CmdtControlPanel from "c/cmdtControlPanel";

// Mock Apex adapters
jest.mock(
  "@salesforce/apex/CmdtTypeRegistry.getSupportedTypes",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/CmdtSchemaService.getFieldDescribes",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/CmdtSchemaService.getTypeInfo",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/CmdtRecordService.getRecords",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/CmdtDeployService.requestDeploy",
  () => ({
    default: jest.fn().mockResolvedValue("MOCK_DEPLOY_ID")
  }),
  { virtual: true }
);

jest.mock(
  "lightning/empApi",
  () => ({
    subscribe: jest.fn().mockResolvedValue({ id: "sub-1" }),
    unsubscribe: jest.fn().mockResolvedValue({}),
    onError: jest.fn()
  }),
  { virtual: true }
);

describe("c-cmdt-control-panel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders card title and defaults to Country_Profile__mdt", () => {
    const element = createElement("c-cmdt-control-panel", {
      is: CmdtControlPanel
    });
    document.body.appendChild(element);

    const card = element.shadowRoot.querySelector("lightning-card");
    expect(card).not.toBeNull();
    expect(card.title).toBe("Custom Metadata Control Panel");
    expect(element.selectedType).toBe("Country_Profile__mdt");
  });

  it("opens create modal on Add Record button click", async () => {
    const element = createElement("c-cmdt-control-panel", {
      is: CmdtControlPanel
    });
    document.body.appendChild(element);

    await Promise.resolve();

    const addButton = element.shadowRoot.querySelector(".add-record-btn");
    expect(addButton).not.toBeNull();
    addButton.click();

    await Promise.resolve();

    const modal = element.shadowRoot.querySelector('section[role="dialog"]');
    expect(modal).not.toBeNull();
  });
});
