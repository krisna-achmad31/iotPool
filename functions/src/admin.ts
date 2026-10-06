import { initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { setGlobalOptions } from 'firebase-functions/v2';

// Region Functions harus sama dengan lokasi Firestore (Console → Firestore → lokasi database).
export const REGION = 'asia-southeast2';

setGlobalOptions({ region: REGION, maxInstances: 10 });

initializeApp();

export const db = getFirestore();
export const rtdb = getDatabase();
export const messaging = getMessaging();
