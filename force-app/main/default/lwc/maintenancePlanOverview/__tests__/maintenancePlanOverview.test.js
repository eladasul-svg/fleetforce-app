import { createElement } from "lwc";
import MaintenancePlanOverview from "c/maintenancePlanOverview";
import { registerApexTestWireAdapter } from "@salesforce/wire-service-jest-util";
import getPlanOverview from "@salesforce/apex/MaintenancePlanOverviewController.getPlanOverview";

const getPlanOverviewAdapter = registerApexTestWireAdapter(getPlanOverview);

const MOCK_PAYLOAD = {
  plan: {
    Id: "a0RWm000001otLpMAI",
    Name: "Kia Sedona & Passenger Fleet 5-Year Gold Plan",
    Asset_Type__c: "Sedan",
    Frequency_Type__c: "Mileage-Based",
    Calendar_Interval_Months__c: 60
  },
  kpis: {
    milestonesCount: 3,
    proceduresCount: 9,
    totalEstimatedCost: 1290,
    totalEstimatedHours: 8.7,
    assignedAssetsCount: 2,
    eligibleAssetsCount: 4
  },
  milestones: [
    {
      id: "m1",
      name: "15,000-Mile Scheduled Service",
      sequence: 1,
      milestoneMileage: 15000,
      milestoneMonths: 12,
      serviceCategory: "Comprehensive Service",
      subtotalCost: 210,
      subtotalHours: 1.8,
      childCount: 2,
      childItems: [
        {
          id: "c1",
          name: "Synthetic Engine Oil & Filter Change",
          itemType: "Fluid & Filter Service",
          estimatedCost: 95,
          estimatedHours: 0.8,
          componentsServiced: "Oil, Filter"
        },
        {
          id: "c2",
          name: "Radial Tire Rotation",
          itemType: "Tire & Brake Service",
          estimatedCost: 65,
          estimatedHours: 0.5,
          componentsServiced: "Rotate 4 tires"
        }
      ]
    }
  ],
  assignedAssets: [
    {
      id: "a1",
      name: "2024 Toyota Camry",
      licensePlate: "CA-25-YW",
      odometer: 16898,
      nextMilestoneName: "30,000-Mile Scheduled Service",
      milestoneStatusLabel: "Due in 13102 mi",
      milestoneBadgeClass: "slds-badge slds-theme_info"
    }
  ],
  eligibleAssets: [
    {
      id: "a2",
      name: "2023 Chevrolet Malibu",
      licensePlate: "IL-701XP",
      odometer: 25400,
      makeModel: "Chevrolet Malibu",
      branchName: "Atlanta Metro Hub"
    }
  ]
};

describe("c-maintenance-plan-overview", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders KPI summary and milestone tree when payload is wired", async () => {
    const element = createElement("c-maintenance-plan-overview", {
      is: MaintenancePlanOverview
    });
    element.recordId = "a0RWm000001otLpMAI";
    document.body.appendChild(element);

    getPlanOverviewAdapter.emit(MOCK_PAYLOAD);

    await Promise.resolve();

    const milestoneHeader = element.shadowRoot.querySelector(
      ".milestone-header a"
    );
    expect(milestoneHeader).not.toBeNull();
    expect(milestoneHeader.textContent.trim()).toBe(
      "15,000-Mile Scheduled Service"
    );

    const taskRows = element.shadowRoot.querySelectorAll(
      ".proc-table tbody tr"
    );
    expect(taskRows.length).toBe(2);
  });

  it("opens modal when Add Milestone button is clicked", async () => {
    const element = createElement("c-maintenance-plan-overview", {
      is: MaintenancePlanOverview
    });
    element.recordId = "a0RWm000001otLpMAI";
    document.body.appendChild(element);

    getPlanOverviewAdapter.emit(MOCK_PAYLOAD);

    await Promise.resolve();

    const addMilestoneBtn = element.shadowRoot.querySelector(
      'lightning-button[data-action="add-milestone"]'
    );
    expect(addMilestoneBtn).not.toBeNull();
    addMilestoneBtn.click();

    await Promise.resolve();

    const modalHeader = element.shadowRoot.querySelector(
      ".slds-modal__header h2"
    );
    expect(modalHeader.textContent.trim()).toBe("Add Service Milestone");
  });
});
