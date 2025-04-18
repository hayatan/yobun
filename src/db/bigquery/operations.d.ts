import { BigQuery, Table } from '@google-cloud/bigquery';
import { ProcessedSlotData } from '../../types/slorepo';

export function saveToBigQuery(table: Table, data: ProcessedSlotData[]): Promise<void>;
export function getBigQueryRowCount(table: Table, holeName: string): Promise<number>;
export function getTable(bigquery: BigQuery, datasetId: string, tableId: string): Promise<Table>; 