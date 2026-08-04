import { LightningElement } from 'lwc';

const STATUS_COLORS = {
    Completed: '#0ca30c',
    'In Progress': '#199e70',
    Planned: '#888780',
    Overdue: '#d03b3b'
};

const STATUS_LABELS = {
    Completed: 'הושלמו',
    'In Progress': 'בתהליך',
    Planned: 'מתוכננות',
    Overdue: 'בחריגה'
};

const STATUS_ICONS = {
    Completed: 'utility:success',
    'In Progress': 'utility:spinner',
    Planned: 'utility:date_input',
    Overdue: 'utility:warning'
};

export default class CaseTaskStatusPanel extends LightningElement {
    statusCounts = {
        Completed: 4,
        'In Progress': 2,
        Planned: 1,
        Overdue: 1
    };

    sampleTasks = [
        {
            id: 't1',
            name: 'בדיקת מסמכי הכנסה ואישורים',
            status: 'Completed'
        },
        {
            id: 't2',
            name: 'בחינת מסמכים והערכת זכאות עקרונית',
            status: 'In Progress'
        },
        {
            id: 't3',
            name: 'אבחון תקלת מים בשטח',
            status: 'Overdue'
        }
    ];

    get totalTasks() {
        return Object.values(this.statusCounts).reduce((sum, n) => sum + n, 0);
    }

    get totalTasksLabel() {
        return `${this.totalTasks} משימות`;
    }

    get tiles() {
        return Object.keys(STATUS_LABELS).map((status) => ({
            key: status,
            label: STATUS_LABELS[status],
            count: this.statusCounts[status],
            color: STATUS_COLORS[status],
            style: `border-right-color: ${STATUS_COLORS[status]};`
        }));
    }

    get tasks() {
        return this.sampleTasks.map((task) => ({
            ...task,
            statusLabel: STATUS_LABELS[task.status],
            color: STATUS_COLORS[task.status],
            icon: STATUS_ICONS[task.status],
            rowStyle: `border-right: 4px solid ${STATUS_COLORS[task.status]};`,
            iconStyle: `--sds-c-icon-color-foreground-default: ${STATUS_COLORS[task.status]};`,
            badgeStyle: `background-color: ${STATUS_COLORS[task.status]}; color: #ffffff;`
        }));
    }

    get donutSegments() {
        const total = this.totalTasks;
        const radius = 15.9155;
        const circumference = 2 * Math.PI * radius;
        let offsetAccum = 0;

        return Object.keys(STATUS_LABELS).map((status) => {
            const count = this.statusCounts[status];
            const fraction = total > 0 ? count / total : 0;
            const dash = fraction * circumference;
            const gap = circumference - dash;
            const segment = {
                key: status,
                color: STATUS_COLORS[status],
                dasharray: `${dash} ${gap}`,
                dashoffset: -offsetAccum
            };
            offsetAccum += dash;
            return segment;
        });
    }

    get trafficLightSummary() {
        return 'רמזור כללי: בטיפול — קיימת משימה אחת בחריגת SLA';
    }
}
