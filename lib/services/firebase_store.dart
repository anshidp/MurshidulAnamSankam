import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_models.dart';
import '../models/subscription_models.dart';

class FirebaseStore {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<House>> getHouses() async {
    final snapshot = await _firestore.collection('houses').get();
    return snapshot.docs
        .map((doc) => House.fromFirestore(doc.data(), doc.id))
        .toList();
  }

  Future<List<PaymentEntry>> getPayments() async {
    final snapshot = await _firestore.collection('payments').get();
    return snapshot.docs
        .map((doc) => PaymentEntry.fromFirestore(doc.data(), doc.id))
        .toList();
  }

  Future<void> saveHouse(House house) async {
    await _firestore
        .collection('houses')
        .doc(house.id)
        .set(house.toFirestore());
  }

  Future<void> deleteHouse(String houseId) async {
    await _firestore.collection('houses').doc(houseId).delete();
  }

  Future<void> savePayment(PaymentEntry payment) async {
    await _firestore
        .collection('payments')
        .doc(payment.id)
        .set(payment.toFirestore());
  }

  Future<void> deletePayment(String paymentId) async {
    await _firestore.collection('payments').doc(paymentId).delete();
  }

  Future<void> saveReceipt(Map<String, dynamic> data, String receiptId) async {
    await _firestore.collection('receipts').doc(receiptId).set(data);
  }

  // ── Staff management ──────────────────────────────────────────────────────

  Future<List<StaffUser>> getStaffList() async {
    final snapshot = await _firestore.collection('staff').get();
    return snapshot.docs
        .map((doc) => StaffUser.fromFirestore(doc.data()))
        .toList();
  }

  Future<void> saveStaff(StaffUser staff) async {
    await _firestore
        .collection('staff')
        .doc(staff.username)
        .set(staff.toFirestore());
  }

  Future<void> deleteStaff(String username) async {
    await _firestore.collection('staff').doc(username).delete();
  }
}
