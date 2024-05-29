String startDate = '2024-05-25', endDate = 'TODAY';
Map<Id, FieloPLT__Member__c> issues = new Map<Id, FieloPLT__Member__c>(
    (List<FieloPLT__Member__c>) Database.query(
        'SELECT ' +
            String.join(new List<String>(SObjectType.FieloPLT__Member__c.fields.getMap().keySet()), ', ') +
        ' FROM FieloPLT__Member__c ' +
        'WHERE ' +
            'Id NOT IN (SELECT FieloPLT__Member__c FROM FieloPLT__Transaction__c WHERE FieloPLT__Reason__c = \'Fielo - Manual Expiration\')' +
            ' AND Id IN (SELECT FieloPLT__Member__c FROM FieloPLT__Point__c WHERE FieloPLT__ExpirationDate__c >= ' + startDate + ' AND FieloPLT__ExpirationDate__c < ' + endDate + ' AND FieloPLT__ExpiredPoints__c > 0) ' +
        ' LIMIT 50'
    )
);
if (issues.isEmpty() == false) {
    Map<Id, Map<Id, FieloPLT__ProgramPointType__c>> programCurrenciesMap = (Map<Id, Map<Id, FieloPLT__ProgramPointType__c>>) FieloPLT.CacheAPI.execute( '{"method":"get","cache":"PROGRAMS","attribute":"programCurrenciesMap"}');
    Map<Id, FieloPLT__PointType__c> currenciesMap = (Map<Id, FieloPLT__PointType__c>) FieloPLT.CacheAPI.execute( '{"method":"get","cache":"CURRENCIES","attribute":"currenciesMap"}');
    Set<String> currencyIds = new Set<String>(), memberBalanceFields = new Set<String>(), transactionBalanceFields = new Set<String>();
    Map<String, String> currencyByTransactionField = new Map<String, String>(), currencyByMemberField = new Map<String, String>();
    Map<Id, Map<Id, List<FieloPLT__Point__c>>> pointsMap = new Map<Id, Map<Id, List<FieloPLT__Point__c>>>();
    List<FieloPLT__Point__c> points =
        Database.queryWithBinds(
            'SELECT FieloPLT__Member__c, FieloPLT__PointType__c, Id FROM FieloPLT__Point__c WHERE FieloPLT__ExpirationDate__c >= ' + startDate + ' AND FieloPLT__ExpirationDate__c < ' + endDate + ' AND FieloPLT__ExpiredPoints__c > 0 AND FieloPLT__ExpirationTransaction__c = null AND FieloPLT__Member__c = :memberIds',
            new Map<String, Object>{'memberIds' => issues.keySet()},
            AccessLevel.USER_MODE
        );
    for (FieloPLT__Point__c p : points) {
        if (pointsMap.containsKey(p.FieloPLT__Member__c)) {
            if (pointsMap.get(p.FieloPLT__Member__c).containsKey(p.FieloPLT__PointType__c)) {
                pointsMap.get(p.FieloPLT__Member__c).get(p.FieloPLT__PointType__c).add(p);
            } else {
                pointsMap.get(p.FieloPLT__Member__c).put(p.FieloPLT__PointType__c, new List<FieloPLT__Point__c>{p});
            }
        } else {
            pointsMap.put(p.FieloPLT__Member__c,
                new Map<Id, List<FieloPLT__Point__c>>{
                    p.FieloPLT__PointType__c => new List<FieloPLT__Point__c>{p}
                }
            );
        }
    }

    for (FieloPLT__Member__c m : issues.values()) {
        for (FieloPLT__ProgramPointType__c ppt : programCurrenciesMap.get(m.FieloPLT__Program__c).values()) {
            FieloPLT__PointType__c curr = currenciesMap.get(ppt.FieloPLT__PointType__c);
            currencyIds.add(curr.Id);
            memberBalanceFields.add(curr.FieloPLT__MemberBalanceField__c);
            transactionBalanceFields.add(curr.FieloPLT__TransactionBalanceField__c);
            currencyByTransactionField.put(curr.FieloPLT__MemberBalanceField__c, curr.Id);
            currencyByMemberField.put(curr.FieloPLT__TransactionBalanceField__c, curr.Id);
        }
    }
    String expiredPointsQuery =
        'SELECT FieloPLT__Member__c, FieloPLT__PointType__c CurrencyId, FieloPLT__PointType__r.FieloPLT__MemberBalanceField__c MemberBalanceField, FieloPLT__PointType__r.FieloPLT__TransactionBalanceField__c TransactionBalanceField, SUM(FieloPLT__ExpiredPoints__c) ExpiredPoints FROM FieloPLT__Point__c WHERE FieloPLT__ExpirationDate__c >= ' + startDate + ' AND FieloPLT__ExpirationDate__c < ' + endDate + ' AND FieloPLT__ExpiredPoints__c > 0 AND FieloPLT__Member__c = :memberIds GROUP BY FieloPLT__Member__c, FieloPLT__PointType__c, FieloPLT__PointType__r.FieloPLT__MemberBalanceField__c, FieloPLT__PointType__r.FieloPLT__TransactionBalanceField__c';
    List<AggregateResult> expiredPointsResult = (List<AggregateResult>) Database.queryWithBinds(
        expiredPointsQuery,
        new Map<String, Object>{'memberIds' => issues.keySet()},
        AccessLevel.USER_MODE
    );
    System.debug('expiredPointsQuery');
    List<String> sumTransactionFields = new List<String>();
    for (String fieldName : transactionBalanceFields) {
        sumTransactionFields.add(
            'SUM(' + fieldName + ') ' + fieldName
        );
    }
    String expirationTransactionsQuery =
        'SELECT FieloPLT__Member__c, ' + String.join(new List<String>(sumTransactionFields), ', ') + ' FROM FieloPLT__Transaction__c WHERE CreatedDate >= ' + startDate + 'T00:00:00Z AND FieloPLT__Type__c >= \'Expiration\' AND FieloPLT__Member__c = :memberIds GROUP BY FieloPLT__Member__c';
    List<AggregateResult> expirationTransactionsResult = (List<AggregateResult>) Database.queryWithBinds(
        expirationTransactionsQuery,
        new Map<String, Object>{'memberIds' => issues.keySet()},
        AccessLevel.USER_MODE
    );
    System.debug('expirationTransactionsQuery');

    Map<Id, Map<Id, Decimal>> expiredPointsByCurrencyByMember = new Map<Id, Map<Id, Decimal>>();
    Map<Id, Map<Id, Decimal>> expirationTransactionsByCurrencyByMember = new Map<Id, Map<Id, Decimal>>();

    for (AggregateResult res : expiredPointsResult) {
        String mId=String.valueOf(res.get('FieloPLT__Member__c')), cId=String.valueOf(res.get('CurrencyId'));
        FieloPLT__PointType__c curr = currenciesMap.get(cId);
        Integer scale = curr.FieloPLT__DecimalsNumber__c.intValue();
        Decimal expPoints = ((Decimal) res.get('ExpiredPoints')).setScale(scale);
        if (expiredPointsByCurrencyByMember.containsKey(mId)) {
            if (expiredPointsByCurrencyByMember.get(mId).containsKey(cId)) {
                Decimal cValue = expiredPointsByCurrencyByMember.get(mId).get(cId);
                expiredPointsByCurrencyByMember.get(mId).put(cId, cValue + expPoints);
            } else {
                expiredPointsByCurrencyByMember.get(mId).put(cId, expPoints);
            }
        } else {
            expiredPointsByCurrencyByMember.put(mId, new Map<Id, Decimal>{
                cId => expPoints
            });
        }
    }
    for (AggregateResult res : expirationTransactionsResult) {
        String mId=String.valueOf(res.get('FieloPLT__Member__c'));

        if (programCurrenciesMap?.get(issues?.get(mId)?.FieloPLT__Program__c)?.isEmpty() == false) {
            for (FieloPLT__ProgramPointType__c ppt : programCurrenciesMap.get(issues.get(mId).FieloPLT__Program__c).values()) {
                FieloPLT__PointType__c curr = currenciesMap.get(ppt.FieloPLT__PointType__c);
                Integer scale = curr.FieloPLT__DecimalsNumber__c.intValue();
                Decimal expPoints = res.get(curr.FieloPLT__TransactionBalanceField__c) == null ? (0.0000).setScale(scale) : ((Decimal)res.get(curr.FieloPLT__TransactionBalanceField__c)).setScale(scale);
                if (expirationTransactionsByCurrencyByMember.containsKey(mId)) {
                    if (expirationTransactionsByCurrencyByMember.get(mId).containsKey(curr.Id)) {
                        Decimal cValue = expirationTransactionsByCurrencyByMember.get(mId).get(curr.Id);
                        expirationTransactionsByCurrencyByMember.get(mId).put(curr.Id, cValue + expPoints);
                    } else {
                        expirationTransactionsByCurrencyByMember.get(mId).put(curr.Id, expPoints);
                    }
                } else {
                    expirationTransactionsByCurrencyByMember.put(mId, new Map<Id, Decimal>{
                        curr.Id => expPoints
                    });
                }
            }
        }
    }
    List<FieloPLT__Transaction__c> tsToInsert = new List<FieloPLT__Transaction__c>();
    List<FieloPLT__Point__c> psToInsert = new List<FieloPLT__Point__c>();
    List<FieloPLT__Point__c> psToUpdate = new List<FieloPLT__Point__c>();
    Map<Id, FieloPLT__Member__c> mToUpdate = new Map<Id, FieloPLT__Member__c>();
    for (FieloPLT__Member__c m : issues.values()) {
        if (expiredPointsByCurrencyByMember.containsKey(m.Id)) {
            for (Id cId : expiredPointsByCurrencyByMember.get(m.Id).keySet()) {
                FieloPLT__PointType__c pt = currenciesMap.get(cId);
                Integer scale = pt.FieloPLT__DecimalsNumber__c.intValue();
                Decimal expPoints = expiredPointsByCurrencyByMember.get(m.Id).get(cId);
                Decimal expTransPoints = expirationTransactionsByCurrencyByMember?.get(m.Id)?.get(cId);
                expTransPoints = expTransPoints != null ? expTransPoints : 0.000;
                if (expPoints.setScale(scale) > (expTransPoints.setScale(scale)*-1)) {
                    FieloPLT__Transaction__c t = new FieloPLT__Transaction__c( FieloPLT__Member__c = m.Id, FieloPLT__Type__c = 'Expiration', FieloPLT__SkipEngine__c = true, FieloPLT__IsProcessed__c = true );
                    t.put(pt.FieloPLT__TransactionBalanceField__c, (expPoints.setScale(scale) - (expTransPoints.setScale(scale)*-1))*-1);
                    t.FieloPLT__Reason__c = 'Fielo - Manual Expiration';
                    tsToInsert.add(t);
                    psToInsert.add(
                        new FieloPLT__Point__c(
                            FieloPLT__Member__c = m.Id,
                            FieloPLT__PointType__c = pt.Id,
                            FieloPLT__TotalPoints__c = (Decimal)t.get(pt.FieloPLT__TransactionBalanceField__c),
                            FieloPLT__OriginalValue__c = (Decimal)t.get(pt.FieloPLT__TransactionBalanceField__c),
                            FieloPLT__ValueCapApplied__c = (Decimal)t.get(pt.FieloPLT__TransactionBalanceField__c),
                            FieloPLT__Transaction__r = t,
                            FieloPLT__Status__c = 'Approved',
                            FieloPLT__MemberBalance__c = (Decimal) issues.get(m.Id).get(pt.FieloPLT__MemberBalanceField__c)
                        )
                    );
                    if (pointsMap?.get(m.Id)?.get(pt.Id)?.isEmpty() == false) {
                        for (FieloPLT__Point__c ep : pointsMap.get(m.Id).get(pt.Id)) {
                            psToUpdate.add(
                                new FieloPLT__Point__c(
                                    Id = ep.Id,
                                    FieloPLT__ExpirationTransaction__r = t
                                )
                            );
                        }
                    }
                    Decimal expiringPoints = (expPoints.setScale(scale) - (expTransPoints.setScale(scale)*-1));
                    Decimal memberBalance = (Decimal)issues.get(m.Id).get(pt.FieloPLT__MemberBalanceField__c);
                    expiringPoints = expiringPoints.setScale(scale);
                    memberBalance = memberBalance.setScale(scale);
                    if (expiringPoints >= memberBalance) {
                        if (!mToUpdate.containsKey(m.Id)) {
                            mToUpdate.put(m.Id, new FieloPLT__Member__c(Id = m.Id));
                        }
                        mToUpdate.get(m.Id).put(pt.FieloPLT__MemberBalanceField__c, 0.000.setScale(scale));
                    }
                } else {
                    FieloPLT__Transaction__c t = new FieloPLT__Transaction__c( FieloPLT__Member__c = m.Id, FieloPLT__Type__c = 'Expiration', FieloPLT__SkipEngine__c = true, FieloPLT__IsProcessed__c = true );
                    t.put(pt.FieloPLT__TransactionBalanceField__c, 0.000.setScale(scale));
                    t.FieloPLT__Reason__c = 'Fielo - Manual Expiration';
                    tsToInsert.add(t);
                }
            }
        }
    }
    FieloPLT__Triggers__c triggers = FieloPLT__Triggers__c.getInstance(UserInfo.getUserId());
    triggers.FieloPLT__Transaction__c = false;
    triggers.FieloPLT__Point__c = false;
    triggers.FieloPLT__Member__c = false;
    upsert triggers;
    insert tsToInsert;
    for (FieloPLT__Point__c p : psToInsert) {
        p.FieloPLT__Transaction__c = p.FieloPLT__Transaction__r.Id;
        p.FieloPLT__Transaction__r = null;
    }
    insert psToInsert;
    for (FieloPLT__Point__c p : psToUpdate) {
        p.FieloPLT__ExpirationTransaction__c = p.FieloPLT__ExpirationTransaction__r.Id;
        p.FieloPLT__ExpirationTransaction__r = null;
    }
    update psToUpdate;
    update mToUpdate.values();
    delete triggers;
}