import { LightningElement, api } from 'lwc';

// Plot area constants (within viewBox 0 0 460 195)
const LEFT = 50, TOP = 15, RIGHT = 440, BOTTOM = 160;
const W = RIGHT - LEFT;   // 390
const H = BOTTOM - TOP;   // 145

function scoreToY(score) {
    return TOP + (100 - Math.min(100, Math.max(0, score || 0))) * H / 100;
}

function dotColor(score) {
    if (score >= 75) return '#2e844a';
    if (score >= 60) return '#dd7a01';
    return '#ea001e';
}

function shortDate(isoString) {
    if (!isoString) return '';
    const d = new Date(isoString);
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

export default class OrgHealthTrendChart extends LightningElement {
    @api trend = [];

    get chartData() {
        const raw = this.trend || [];
        if (raw.length < 2) return null;

        const scans = [...raw].reverse(); // oldest → newest left to right
        const n = scans.length;

        const points = scans.map((s, i) => {
            const x = parseFloat((n > 1 ? LEFT + i * W / (n - 1) : LEFT + W / 2).toFixed(1));
            const y = parseFloat(scoreToY(s.CompositeScore__c).toFixed(1));
            return {
                key: `pt-${i}`,
                labelKey: `lb-${i}`,
                x,
                y,
                dotColor: dotColor(s.CompositeScore__c),
                dateLabel: shortDate(s.ScanStartTime__c),
                labelRotate: `rotate(-35, ${x}, 178)`,
                tooltip: `Score: ${Math.round(s.CompositeScore__c || 0)}  •  ${shortDate(s.ScanStartTime__c)}`
            };
        });

        const polylinePoints = points.map(p => `${p.x},${p.y}`).join(' ');
        return { points, polylinePoints };
    }

    // Zone geometry — split at grade thresholds 75 (B) and 60 (C)
    get greenZoneHeight() { return scoreToY(75) - TOP; }          // top to B line
    get amberZoneTop()    { return scoreToY(75); }
    get amberZoneHeight() { return scoreToY(60) - scoreToY(75); }
    get redZoneTop()      { return scoreToY(60); }
    get redZoneHeight()   { return BOTTOM - scoreToY(60); }

    get thresholdLines() {
        return [
            { label: 'A', y: scoreToY(90), labelY: scoreToY(90), textKey: 'tl-a', color: '#2e844a' },
            { label: 'B', y: scoreToY(75), labelY: scoreToY(75), textKey: 'tl-b', color: '#3ba755' },
            { label: 'C', y: scoreToY(60), labelY: scoreToY(60), textKey: 'tl-c', color: '#dd7a01' },
            { label: 'D', y: scoreToY(40), labelY: scoreToY(40), textKey: 'tl-d', color: '#ea001e' }
        ];
    }
}
