# 🏥 Telemedicine Payment Gateway

A secure, decentralized payment gateway built on Stacks blockchain for virtual medical consultations with built-in escrow and dispute resolution.

## ✨ Features

- 👩‍⚕️ **Doctor Registration**: Medical professionals can register with specialty and consultation rates
- 👤 **Patient Registration**: Secure patient onboarding system
- 💰 **Escrow Payments**: Automatic escrow system that holds payments until consultation completion
- 🔒 **Dispute Resolution**: Built-in arbitration system for payment disputes
- ⏰ **Consultation Management**: Track consultation status from booking to completion
- 🌍 **Cross-border Support**: Bitcoin-based payments for global accessibility
- 📊 **Analytics**: Track consultation metrics and platform statistics

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet (for testing)

### Installation

1. Clone the repository:
```bash
git clone <your-repo-url>
cd telemedicine-payment-gateway
```

2. Check contract syntax:
```bash
clarinet check
```

3. Run tests:
```bash
clarinet test
```

## 📋 Usage

### For Doctors 👩‍⚕️

1. **Register as a Doctor**:
```clarity
(contract-call? .telemedicine-payment-gateway register-doctor 
    u"Dr. Jane Smith" 
    u"Cardiology" 
    u1000000)  ;; Rate in microSTX
```

2. **Set Availability**:
```clarity
(contract-call? .telemedicine-payment-gateway set-doctor-availability 
    true 
    u1000 
    u144)  ;; Available for 1 day blocks
```

3. **Start Consultation**:
```clarity
(contract-call? .telemedicine-payment-gateway start-consultation u1)
```

4. **Complete Consultation**:
```clarity
(contract-call? .telemedicine-payment-gateway complete-consultation 
    u1 
    (some u"Patient shows good progress"))
```

### For Patients 🤒

1. **Register as a Patient**:
```clarity
(contract-call? .telemedicine-payment-gateway register-patient u"John Doe")
```

2. **Book Consultation**:
```clarity
(contract-call? .telemedicine-payment-gateway book-consultation 'SP2J6Z...)  ;; Doctor's address
```

3. **Raise Dispute** (if needed):
```clarity
(contract-call? .telemedicine-payment-gateway raise-dispute 
    u1 
    u"Doctor did not show up for scheduled consultation")
```

### For Platform Owners 🛡️

1. **Resolve Disputes**:
```clarity
(contract-call? .telemedicine-payment-gateway resolve-dispute 
    u1 
    'SP1234...  ;; Winner's address
    u"Evidence supports patient's claim")
```

2. **Toggle Platform Pause**:
```clarity
(contract-call? .telemedicine-payment-gateway toggle-platform-pause)
```

## 🔍 Read-Only Functions

### Get Doctor Information
```clarity
(contract-call? .telemedicine-payment-gateway get-doctor 'SP2J6Z...)
```

### Get Consultation Details
```clarity
(contract-call? .telemedicine-payment-gateway get-consultation u1)
```

### Calculate Consultation Fee
```clarity
(contract-call? .telemedicine-payment-gateway calculate-consultation-fee 'SP2J6Z...)
```

### Check Platform Statistics
```clarity
(contract-call? .telemedicine-payment-gateway get-platform-stats)
```

## 💡 Key Concepts

### 💸 Payment Flow
1. **Booking**: Patient pays consultation fee + platform fee (3%) into escrow
2. **Consultation**: Doctor provides medical service
3. **Completion**: Payment automatically released to doctor
4. **Dispute**: If issues arise, platform owner arbitrates

### ⚡ Fee Structure
- Platform fee: 3% of consultation rate
- Consultation timeout: 144 blocks (~1 day)
- Dispute resolution: 1008 blocks (~1 week)

### 🔐 Security Features
- Escrow system prevents payment fraud
- Role-based access control
- Dispute resolution mechanism
- Platform pause functionality for emergencies

## 🏗️ Contract Architecture

### Data Structures
- **doctors**: Medical professional profiles and rates
- **patients**: Patient registration data
- **consultations**: Consultation sessions and status
- **escrow**: Payment holding and release mechanism
- **disputes**: Dispute cases and resolutions

### Status Flow
```
booked → in-progress → completed
   ↓
disputed → resolved
```

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

Test specific scenarios:
- Doctor registration and rate updates
- Patient booking and payment flows
- Escrow release mechanisms
- Dispute resolution process

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For support and questions:
- Create an issue on GitHub
- Join our Discord community
- Check the [documentation](docs/)

---

Built with ❤️ for global healthcare accessibility
