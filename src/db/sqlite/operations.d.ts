import { Database } from 'sqlite3';
import { ProcessedSlotData } from '../../types/slorepo';

export function isDiffDataExists(db: Database, date: string, holeName: string): Promise<boolean>;
export function saveDiffData(db: Database, data: ProcessedSlotData[]): Promise<void>;
export function getDiffData(db: Database, date: string, holeName: string): Promise<ProcessedSlotData[]>; 