import { LightningElement, api } from 'lwc';

const R = 80, CX = 100, CY = 100;

export default class OrgHealthScoreGauge extends LightningElement {
    @api score = 0;
    @api grade = '--';
    @api label = 'Overall Health Score';

    get hasFill() {
        return (this.score || 0) > 0;
    }

    get fillPath() {
        const s = Math.min(99.9, Math.max(0, this.score || 0));
        if (s === 0) return '';
        const angleRad = (180 - s * 1.8) * (Math.PI / 180);
        const ex = (CX + R * Math.cos(angleRad)).toFixed(3);
        const ey = (CY - R * Math.sin(angleRad)).toFixed(3);
        // sweep-flag=0 → counterclockwise → goes through the top of the arc
        return `M 20 100 A ${R} ${R} 0 0 0 ${ex} ${ey}`;
    }

    get fillColor() {
        const s = this.score || 0;
        if (s >= 75) return '#2e844a';
        if (s >= 60) return '#dd7a01';
        return '#ea001e';
    }

    get displayScore() {
        return this.score != null ? Math.round(this.score) : '--';
    }

    get ariaLabel() {
        return `Health score ${this.displayScore}, grade ${this.grade}`;
    }
}
