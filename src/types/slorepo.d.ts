export interface Hole {
    name: string;
    code: string;
}

export interface Machine {
    name: string;
    encodedName: string;
}

export interface SlotData {
    date: string;
    hole: string;
    machine: string;
    machineNumber: string;
    diff: string;
    game: string;
    big: string;
    reg: string;
    combinedRate: string;
    graphData: number[];
    maxMY?: number;
    maxMDia?: number;
    win?: number;
    win1000?: number;
    win2000?: number;
    win5000?: number;
    win7000?: number;
    win10000?: number;
}

export interface ProcessedSlotData extends SlotData {
    diff: number;
    game: number;
    maxMY: number;
    maxMDia: number;
    win: number;
    win1000: number;
    win2000: number;
    win5000: number;
    win7000: number;
    win10000: number;
} 